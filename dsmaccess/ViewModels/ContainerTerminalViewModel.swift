//
//  ContainerTerminalViewModel.swift
//  dsmaccess
//
//  Runs one shell session inside a container: opens it on the monitor socket, attaches the
//  terminal socket to it, and keeps the output readable.
//

import Foundation
import Observation

@MainActor
@Observable
final class ContainerTerminalViewModel {
    enum Phase: Equatable {
        case idle
        case opening
        case running
        /// The session is over, with what ended it.
        case ended(String)
    }

    let containerName: String
    private(set) var phase = Phase.idle
    private(set) var output = ""
    /// Command run to open the session. DSM offers the same field, with `/bin/bash` in it.
    var command = "/bin/sh"
    var input = ""
    var errorMessage: String?

    private let session: SessionStore
    private var monitor: ContainerTerminalSocket?
    private var terminal: ContainerTerminalSocket?
    private var monitorTask: Task<Void, Never>?
    private var terminalTask: Task<Void, Never>?
    private var openingTimeout: Task<Void, Never>?
    private var announcement: Task<Void, Never>?
    private var buffer = TerminalOutputBuffer()
    /// Sessions the container already had, so the one opened here can be told apart.
    private var previousSessionIDs: Set<String> = []
    private var hasAskedForSession = false
    private var ttyID: String?
    private var attached = false
    private var pendingLines: [String] = []
    /// Set once the address of the connection has had its handshake refused, and kept: the
    /// answer will not change while this screen is open.
    private var usesFallbackAddress = false

    /// Width the shell is told about, measured: at this many columns `ls` prints one entry per
    /// line, where 20 still gives two columns and 80 gives nine.
    private static let columns = 12
    private static let rows = 24

    /// Beyond this, the output is summarised rather than spoken: a listing of several hundred
    /// lines would otherwise leave VoiceOver reading for minutes, with no way to stop it.
    private static let spokenLineLimit = 20

    init(session: SessionStore, containerName: String) {
        self.session = session
        self.containerName = containerName
    }

    var isRunning: Bool { phase == .running }

    var canSend: Bool { isRunning && attached }

    /// Opens a shell in the container and attaches to it.
    func open() async {
        guard phase == .idle || isEnded else { return }
        reset()
        phase = .opening
        VoiceOver.announce(
            String(localized: "containers.terminal.opening", defaultValue: "Opening a session in \(containerName)"),
            category: .progress,
            priority: .low
        )

        let socket: ContainerTerminalSocket
        do {
            socket = try await session.withClient { [usesFallbackAddress] in
                try $0.containerTerminalSocket(
                    container: containerName,
                    role: .monitor,
                    usingFallbackAddress: usesFallbackAddress
                )
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            fail(with: (error as? DSMError)?.errorDescription ?? error.localizedDescription)
            return
        }

        monitor = socket
        let events = socket.start()
        monitorTask = Task { [weak self] in
            for await event in events {
                // A socket left behind by a retry can still have events queued, and acting on
                // them would open a second session over the one that just succeeded.
                guard let self, monitor === socket else { return }
                await handle(monitor: event)
            }
        }
        watchOpening()
    }

    /// Sends the line to the shell, with the carriage return a real terminal would add.
    func send() async {
        let line = input
        guard canSend, let terminal else { return }
        input = ""
        openBlock(for: line)
        do {
            try await terminal.write(line + "\r")
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = String(
                localized: "containers.terminal.send_failed",
                defaultValue: "The command could not be sent: \((error as? DSMError)?.errorDescription ?? error.localizedDescription)"
            )
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }

    /// Sends a control character, so a running command can be interrupted as in a terminal.
    func interrupt() async {
        guard canSend, let terminal else { return }
        openBlock(for: String(localized: "containers.terminal.block.interrupt"))
        try? await terminal.write("\u{03}")
    }

    /// Opens the block of one exchange: what was sent, then the label the answer follows.
    private func openBlock(for line: String) {
        buffer.startNewBlock()
        buffer.appendOwnLine(String(
            localized: "containers.terminal.block.sent",
            defaultValue: "You: \(line)"
        ))
        buffer.appendOwnLine(String(localized: "containers.terminal.block.received"))
        output = buffer.text
    }

    /// Settles the shell into something readable, both measured on DSM 7.4:
    ///
    /// - the terminal is declared narrow, so the commands that lay their output out in columns
    ///   — `ls` above all — print one entry per line instead. Programs with fixed columns
    ///   (`df`, `ps`) are unaffected: they print the same bytes at any width.
    /// - the shell is asked to stop echoing what it is sent, since the screen already shows
    ///   that line as the user's own. Sent while the terminal is still wide, so the shell does
    ///   not wrap the echo of this very command.
    ///
    /// Whatever this exchange printed is then dropped: it is housekeeping, not the session.
    private func prepareSession() async {
        guard let terminal else { return }
        try? await terminal.resize(rows: Self.rows, columns: 80)
        try? await terminal.write("stty -echo\r")
        try? await Task.sleep(for: .milliseconds(400))
        try? await terminal.resize(rows: Self.rows, columns: Self.columns)
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        buffer.removeAll()
        output = ""
        pendingLines = []
    }

    /// Ends the session and closes both sockets. Deleting the session leaves nothing running
    /// in the container: the shell would otherwise stay listed on the NAS.
    func close() async {
        announcement?.cancel()
        announcement = nil
        openingTimeout?.cancel()
        openingTimeout = nil

        if let ttyID, attached, let monitor {
            try? await monitor.deleteSession(id: ttyID)
        }
        closeSockets()
        if case .running = phase {
            phase = .ended(String(localized: "containers.terminal.ended.closed", defaultValue: "Session closed"))
        }
    }

    private func closeSockets() {
        terminalTask?.cancel()
        monitorTask?.cancel()
        terminal?.close()
        monitor?.close()
        terminalTask = nil
        monitorTask = nil
        terminal = nil
        monitor = nil
        attached = false
    }

    private var isEnded: Bool {
        if case .ended = phase { return true }
        return false
    }

    private func reset() {
        buffer.removeAll()
        output = ""
        errorMessage = nil
        previousSessionIDs = []
        hasAskedForSession = false
        ttyID = nil
        attached = false
        pendingLines = []
    }

    private func handle(monitor event: ContainerTerminalEvent) async {
        switch event {
        case .entered(let accepted):
            if !accepted {
                fail(with: String(
                    localized: "containers.terminal.enter_failed",
                    defaultValue: "The terminal service refused \(containerName)"
                ))
            }
        case .sessions(let sessions):
            await handle(sessions: sessions)
        case .created(let created):
            if !created {
                fail(with: String(localized: "containers.terminal.create_failed"))
            }
        case .failed(let message):
            fail(with: message)
        case .addressRefused(let message):
            await retryElsewhereOrFail(with: message)
        case .closed:
            if phase == .opening {
                fail(with: String(localized: "containers.terminal.create_failed"))
            }
        case .attached, .output, .renamed:
            break
        }
    }

    /// DSM turns the handshake down when the address it was reached by is not one it knows as
    /// its own — QuickConnect's local route is named that way. The NAS answers on its plain
    /// QuickConnect name, so that one is worth a single try before giving up.
    private func retryElsewhereOrFail(with message: String) async {
        guard !usesFallbackAddress,
              let fallback = try? await session.withClient({ $0.terminalFallbackAddress }),
              fallback != nil else {
            fail(with: message)
            return
        }
        usesFallbackAddress = true
        closeSockets()
        phase = .idle
        await open()
    }

    private func handle(sessions: [ContainerTerminalTTY]) async {
        guard ttyID == nil else {
            // Losing the session from the list means the shell ended on the NAS side.
            if let ttyID, attached, !sessions.contains(where: { $0.id == ttyID }) {
                end(with: String(localized: "containers.terminal.ended.exited", defaultValue: "Session ended"))
            }
            return
        }

        guard hasAskedForSession else {
            previousSessionIDs = Set(sessions.map(\.id))
            hasAskedForSession = true
            do {
                try await monitor?.createSession(command: command)
            } catch {
                guard !DSMError.isCancellation(error) else { return }
                fail(with: (error as? DSMError)?.errorDescription ?? error.localizedDescription)
            }
            return
        }

        guard let opened = sessions.first(where: { !previousSessionIDs.contains($0.id) }) else {
            return
        }
        ttyID = opened.id
        await attachTerminal(to: opened.id)
    }

    private func attachTerminal(to id: String) async {
        guard terminal == nil else { return }
        let socket: ContainerTerminalSocket
        do {
            socket = try await session.withClient { [usesFallbackAddress] in
                try $0.containerTerminalSocket(
                    container: containerName,
                    role: .terminal,
                    usingFallbackAddress: usesFallbackAddress
                )
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            fail(with: (error as? DSMError)?.errorDescription ?? error.localizedDescription)
            return
        }

        terminal = socket
        let events = socket.start()
        terminalTask = Task { [weak self] in
            for await event in events {
                guard let self, terminal === socket else { return }
                await handle(terminal: event, ttyID: id)
            }
        }
    }

    private func handle(terminal event: ContainerTerminalEvent, ttyID: String) async {
        switch event {
        case .entered(let accepted):
            guard accepted else {
                fail(with: String(
                    localized: "containers.terminal.enter_failed",
                    defaultValue: "The terminal service refused \(containerName)"
                ))
                return
            }
            try? await terminal?.attach(id: ttyID)
        case .attached(let code):
            await handleAttachment(code: code)
        case .output(let text):
            append(text)
        case .closed(let code):
            // A shell the image does not have prints the runtime's complaint, then ends here.
            end(with: code == ContainerTerminalCode.execEnded
                ? String(localized: "containers.terminal.ended.exited", defaultValue: "Session ended")
                : String(localized: "containers.terminal.ended.closed", defaultValue: "Session closed"))
        case .failed(let message):
            fail(with: message)
        case .addressRefused(let message):
            await retryElsewhereOrFail(with: message)
        case .sessions, .created, .renamed:
            break
        }
    }

    private func handleAttachment(code: Int) async {
        switch code {
        case ContainerTerminalCode.attachSucceeded:
            attached = true
            openingTimeout?.cancel()
            openingTimeout = nil
            phase = .running
            await prepareSession()
            VoiceOver.announce(
                String(
                    localized: "containers.terminal.opened",
                    defaultValue: "Session open in \(containerName), running \(command)"
                ),
                category: .result,
                priority: .high
            )
        case ContainerTerminalCode.attachedElsewhere, ContainerTerminalCode.clientAttach:
            fail(with: String(localized: "containers.terminal.attach_taken"))
        default:
            fail(with: String(localized: "containers.terminal.attach_failed"))
        }
    }

    private func append(_ text: String) {
        let completed = buffer.append(text)
        output = buffer.text
        pendingLines.append(contentsOf: completed)
        scheduleAnnouncement()
    }

    /// Speaks the output once it has settled: announcing every chunk would cut the previous
    /// sentence in half, and a shell sends its answer in several of them.
    private func scheduleAnnouncement() {
        announcement?.cancel()
        announcement = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            speakPendingOutput()
        }
    }

    private func speakPendingOutput() {
        let lines = pendingLines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        pendingLines = []
        guard !lines.isEmpty else { return }

        if lines.count > Self.spokenLineLimit {
            VoiceOver.announce(
                String(
                    localized: "containers.terminal.output_summary",
                    defaultValue: "\(lines.count) lines received, read them in the output"
                ),
                category: .result
            )
        } else {
            VoiceOver.announce(lines.joined(separator: "\n"), category: .result)
        }
    }

    /// Nothing on this screen times out on its own: without this, a service that never
    /// answers would leave the window silent on “Opening a session”.
    private func watchOpening() {
        openingTimeout?.cancel()
        openingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, phase == .opening else { return }
            fail(with: String(localized: "containers.terminal.timeout"))
            await close()
        }
    }

    private func fail(with message: String) {
        guard !isEnded else { return }
        errorMessage = message
        phase = .ended(message)
        attached = false
        VoiceOver.announce(message, category: .error, priority: .high)
    }

    private func end(with message: String) {
        guard !isEnded else { return }
        attached = false
        phase = .ended(message)
        VoiceOver.announce(message, category: .result, priority: .high)
    }
}
