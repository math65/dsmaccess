//
//  ContainerTerminalSocket.swift
//  dsmaccess
//
//  One WebSocket to Container Manager's terminal service. Its messages are JSON arrays whose
//  first element names the event, in both directions: ["enter", name, role], ["data", text].
//

import Foundation

@MainActor
final class ContainerTerminalSocket {
    private let task: URLSessionWebSocketTask
    private let container: String
    private let role: ContainerTerminalRole
    private var events: AsyncStream<ContainerTerminalEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?

    init(task: URLSessionWebSocketTask, container: String, role: ContainerTerminalRole) {
        self.task = task
        self.container = container
        self.role = role
    }

    deinit {
        task.cancel(with: .goingAway, reason: nil)
    }

    /// Opens the socket, enters the container in this socket's role, and reports what the
    /// service sends until it closes. Call once per socket.
    func start() -> AsyncStream<ContainerTerminalEvent> {
        let (stream, continuation) = AsyncStream<ContainerTerminalEvent>.makeStream()
        events = continuation
        task.resume()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await emit(["enter", container, role.rawValue])
            } catch {
                continuation.yield(failure(for: error))
                continuation.finish()
                return
            }
            await receive(into: continuation)
        }
        return stream
    }

    /// Opens a shell in the container. Only a monitor socket may do this.
    func createSession(command: String) async throws {
        try await emit(["create", command])
    }

    /// Ends a session. Only a monitor socket may do this, and only for a session that has
    /// been attached to: the NAS silently ignores the request for one that never started.
    func deleteSession(id: String) async throws {
        try await emit(["delete", id])
    }

    /// Takes hold of a session. `force` takes it over from another client, which is what
    /// answers an `attachedElsewhere` outcome.
    func attach(id: String, force: Bool = false) async throws {
        try await emit(["attach", id, force])
    }

    func resize(rows: Int, columns: Int) async throws {
        try await emit(["resize", rows, columns])
    }

    /// Sends keystrokes. A command line needs its own carriage return, as on a real terminal.
    func write(_ text: String) async throws {
        try await emit(["data", text])
    }

    func close() {
        receiveTask?.cancel()
        receiveTask = nil
        task.cancel(with: .goingAway, reason: nil)
        events?.finish()
        events = nil
    }

    private func emit(_ payload: [Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DSMError.invalidResponse
        }
        try await task.send(.string(text))
    }

    private func receive(into continuation: AsyncStream<ContainerTerminalEvent>.Continuation) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard let event = Self.event(from: message) else { continue }
                continuation.yield(event)
                if case .closed = event { break }
            } catch {
                if !Task.isCancelled, !DSMError.isCancellation(error) {
                    continuation.yield(failure(for: error))
                }
                break
            }
        }
        continuation.finish()
    }

    nonisolated static func event(
        from message: URLSessionWebSocketTask.Message
    ) -> ContainerTerminalEvent? {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let payload): data = payload
        @unknown default: return nil
        }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let name = array.first as? String else { return nil }
        let arguments = Array(array.dropFirst())

        switch name {
        case "enter":
            return .entered(arguments.first as? Bool ?? false)
        case "create":
            return .created(arguments.first as? Bool ?? false)
        case "list":
            return .sessions(sessions(in: arguments.first as? [Any] ?? []))
        case "attach":
            return .attached(code: arguments.first as? Int ?? ContainerTerminalCode.unknown)
        case "data":
            guard let text = arguments.first as? String else { return nil }
            return .output(text)
        case "title":
            guard arguments.count >= 2,
                  let id = arguments[0] as? String,
                  let title = arguments[1] as? String else { return nil }
            return .renamed(id: id, title: title)
        case "close":
            return .closed(code: arguments.first as? Int ?? ContainerTerminalCode.unknown)
        default:
            return nil
        }
    }

    /// The list arrives flattened: identifier, title, identifier, title…
    private nonisolated static func sessions(in payload: [Any]) -> [ContainerTerminalTTY] {
        stride(from: 0, to: payload.count - 1, by: 2).compactMap { index in
            guard let id = payload[index] as? String,
                  let title = payload[index + 1] as? String else { return nil }
            return ContainerTerminalTTY(id: id, title: title)
        }
    }

    private func failure(for error: Error) -> ContainerTerminalEvent {
        let message = Self.description(of: error, host: host)
        guard host != nil, Self.isAddressRefusal(error) else { return .failed(message) }
        return .addressRefused(message)
    }

    nonisolated static func isAddressRefusal(_ error: Error) -> Bool {
        (error as? URLError)?.code == .badServerResponse
    }

    /// Measured on DSM 7.4 with CSRF protection on: the very same session and request are
    /// accepted through the address the NAS declares as its own and refused, before any
    /// authentication, through its QuickConnect name. The refusal reaches URLSession as a bad
    /// server response, which says nothing a user could act on.
    nonisolated static func description(of error: Error, host: String?) -> String {
        if let host, (error as? URLError)?.code == .badServerResponse {
            return String(
                localized: "containers.terminal.address_refused",
                defaultValue: "DSM refused the terminal for the address “\(host)”. Container Manager only accepts it from an address the NAS recognises as its own: connect with the address you use in your browser."
            )
        }
        if let error = error as? DSMError, let description = error.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private var host: String? { task.originalRequest?.url?.host }
}
