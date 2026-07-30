//
//  ConnectionsViewModel.swift
//  dsmaccess
//
//  Connections tab of the resource monitor: who is connected to the NAS, from where and
//  over which protocol, and the disconnection of open sessions.
//

import Foundation
import Observation

@MainActor
@Observable
final class ConnectionsViewModel {
    private(set) var connections: [NASConnection] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// Sessions being disconnected, so the button can be disarmed for the duration of the call.
    private(set) var busyIDs: Set<String> = []

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if connections.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { try await $0.connections() }
            guard generation == loadGeneration else { return }
            // The visible sort belongs to the table; here only a stable starting order is
            // fixed, from the most recent session to the oldest.
            connections = result.sorted {
                ($0.openedAt ?? .distantPast) > ($1.openedAt ?? .distantPast)
            }
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    /// Disconnects the given sessions in a single call, as DSM does. Entries the NAS declares
    /// non-disconnectable are dropped here: sending them would fail the whole batch.
    func kick(_ selection: [NASConnection]) async -> DSMOperationOutcome {
        let kickable = selection.filter { $0.kickReference != nil }
        guard !kickable.isEmpty else {
            return .failure(String(localized: "connections.disconnect.unsupported_selection"))
        }

        busyIDs.formUnion(kickable.map(\.id))
        defer { busyIDs.subtract(kickable.map(\.id)) }

        do {
            let references = kickable.compactMap(\.kickReference)
            try await session.withClient { try await $0.kickConnections(references) }
            // The list is reloaded rather than patched in place: disconnecting a web session
            // sometimes closes others from the same device, and only the NAS knows which.
            await load()
            if let only = kickable.first, kickable.count == 1 {
                return .success(
                    String(localized: "connections.disconnect.success", defaultValue: "\(accountText(for: only))’s session disconnected")
                )
            }
            return .success(String(localized: "connections.disconnect.success_multiple", defaultValue: "\(kickable.count) sessions disconnected"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "connections.disconnect.error", defaultValue: "Could not disconnect: \(reason)"))
        }
    }

    /// True when the selection contains a web session belonging to the account the app is
    /// signed in with. `is_current_connected` is useless here: verified on DSM 7.4, the NAS
    /// only raises it for its own web client. Comparing the account is therefore the only
    /// signal available, and it may designate a session other than the app's own.
    func mayCloseOwnSession(_ selection: [NASConnection]) -> Bool {
        guard let account = session.activeProfile?.account else { return false }
        return selection.contains {
            $0.isWebSession
                && $0.account?.caseInsensitiveCompare(account) == .orderedSame
        }
    }

    func canKick(_ connection: NASConnection) -> Bool {
        connection.kickReference != nil && !busyIDs.contains(connection.id)
    }

    func accountText(for connection: NASConnection) -> String {
        connection.account ?? String(localized: "connections.account.unknown")
    }

    // MARK: - Values DSM does not display
    //
    // The NAS has always returned them. A dash when they are empty, as everywhere else in
    // this module: the NAS only fills in the client and the location for some sessions, and
    // a local access produces neither.

    func clientText(for connection: NASConnection) -> String {
        connection.userAgent ?? "—"
    }

    func locationText(for connection: NASConnection) -> String {
        connection.location ?? "—"
    }

    /// Knowing that a session was opened *without* a second factor is at least as useful as
    /// the opposite: the column always says something. The trusted device is stated in the
    /// same column, not deserving one of its own.
    func twoFactorText(for connection: NASConnection) -> String {
        switch (connection.usesTwoFactor, connection.isTrustedDevice) {
        case (true, true): String(localized: "connections.trusted_device.yes")
        case (true, false): String(localized: "common.answer.yes")
        case (false, true): String(localized: "connections.trusted_device.no")
        case (false, false): String(localized: "common.answer.no")
        }
    }

    /// Timestamp rendered in the Mac's language. A dash when DSM sent a form we could not
    /// read: the connection stays listed, with no invented date.
    func openedAtText(for connection: NASConnection) -> String {
        guard let openedAt = connection.openedAt else { return "—" }
        return openedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "connections.summary.open_count", defaultValue: "\(connections.count) open connections")
    }
}
