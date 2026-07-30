//
//  SessionStore.swift
//  dsmaccess
//
//  Shared session state of the app: connected client, capabilities and host.
//  Observed by RootView to switch between the sign-in screen and the content.
//

import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    /// Endpoint of the currently connected NAS (nil when disconnected).
    private(set) var endpoint: DSMEndpoint?
    /// Stable identity that produced the current endpoint.
    private(set) var connectionTarget: NASConnectionTarget?
    /// The client owns the DSM session and remains the only source of the SID and SynoToken.
    private var client: DSMClientProtocol?
    private var generation = 0
    /// APIs actually exposed by DSM and its installed packages.
    private(set) var capabilities = DSMCapabilities()
    /// Saved NAS devices. Passwords stay exclusively in the Keychain.
    private(set) var profiles: [NASProfile]
    private(set) var activeProfileID: UUID?
    private var requestedProfileID: UUID?
    private var requestsBlankConnection = false

    /// Reason for a forced disconnection, consumed by the sign-in screen.
    private(set) var disconnectionMessage: String?

    /// Notice presented in the connected interface when the session was automatically
    /// re-established after an expiration: without it, the user returns to the overview
    /// without knowing that their operation was interrupted.
    private(set) var reconnectionNotice: String?

    var isLoggedIn: Bool { client != nil }

    var activeProfile: NASProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    var connectionProfile: NASProfile? {
        guard !requestsBlankConnection else { return nil }
        let profileID = requestedProfileID ?? Preferences.selectedNASProfileID
        guard let profileID else { return nil }
        return profiles.first { $0.id == profileID }
    }

    init() {
        profiles = Preferences.nasProfiles
        activeProfileID = nil
        requestedProfileID = Preferences.selectedNASProfileID
        if let profile = profiles.first(where: { $0.id == requestedProfileID }) {
            persistLegacyConnectionPreferences(for: profile)
        }
    }

    /// Records an open session after a successful login.
    func establish(
        target: NASConnectionTarget,
        endpoint: DSMEndpoint,
        client: DSMClientProtocol,
        capabilities: DSMCapabilities,
        account: String,
        remembersPassword: Bool
    ) {
        connectionTarget = target
        self.endpoint = endpoint
        self.client = client
        self.capabilities = capabilities
        generation += 1
        disconnectionMessage = nil
        registerProfile(
            target: target,
            account: account,
            remembersPassword: remembersPassword
        )
    }

    /// Runs any operation with the session's client and invalidates the whole state if DSM
    /// reports an expiration. Views never handle the SID.
    func withClient<Value>(
        _ operation: (DSMClientProtocol) async throws -> Value
    ) async throws -> Value {
        guard let client else {
            // A task belonging to a view that is gone can reach this point after a
            // deliberate disconnection. It must not turn that logout into a bogus
            // session expiration on the sign-in screen.
            throw DSMError.cancelled
        }
        let operationGeneration = generation
        do {
            let value = try await operation(client)
            guard operationGeneration == generation, self.client === client else {
                throw DSMError.cancelled
            }
            return value
        } catch DSMError.sessionExpired {
            guard operationGeneration == generation, self.client === client else {
                throw DSMError.cancelled
            }
            expireSession()
            throw DSMError.sessionExpired
        }
    }

    /// Asks the host whether it has finished booting, without going through `withClient`:
    /// during a reboot there is no session left, and the generation guard would reject the
    /// answer. Returns false if the NAS is unreachable — the expected case while it reboots.
    func isNASBackOnline() async -> Bool {
        guard let client else { return false }
        return await client.isNASBackOnline()
    }

    func logout() async {
        let activeClient = client
        forgetStoredSession()
        clear()
        try? await activeClient?.logout()
    }

    /// A session closed or invalidated by the NAS must not be retried at the next launch:
    /// the app would waste a round trip, and the user would lose an explanation.
    private func forgetStoredSession() {
        guard let profile = activeProfile else { return }
        CredentialStore.forgetSession(account: profile.account, target: profile.connection)
    }

    func prepareConnection(to profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        requestedProfileID = profileID
        requestsBlankConnection = false
        persistLegacyConnectionPreferences(for: profile)
        Preferences.selectedNASProfileID = profileID
    }

    func prepareNewNAS() {
        requestedProfileID = nil
        requestsBlankConnection = true
        Preferences.lastHost = ""
        Preferences.lastPort = nil
        Preferences.lastUseHTTPS = true
        Preferences.lastAccount = ""
        Preferences.rememberPassword = false
    }

    func renameProfile(_ profileID: UUID, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = profiles.firstIndex(where: { $0.id == profileID }) else {
            return
        }
        profiles[index].name = name
        persistProfiles()
    }

    func updateActiveProfileDefaultName(to modelName: String) {
        let name = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let activeProfileID,
              let index = profiles.firstIndex(where: { $0.id == activeProfileID }),
              profiles[index].name == profiles[index].connection.defaultProfileName else { return }
        profiles[index].name = name
        persistProfiles()
    }

    func removeProfile(_ profileID: UUID) {
        guard profileID != activeProfileID,
              let profile = profiles.first(where: { $0.id == profileID }) else { return }
        CredentialStore.forget(account: profile.account, target: profile.connection)
        profiles.removeAll { $0.id == profileID }
        if requestedProfileID == profileID { requestedProfileID = nil }
        if Preferences.selectedNASProfileID == profileID {
            Preferences.selectedNASProfileID = profiles.first?.id
        }
        persistProfiles()
        Preferences.rememberPassword = activeProfile?.remembersPassword
            ?? connectionProfile?.remembersPassword
            ?? false
    }

    func forgetActiveCredentials() {
        guard let activeProfileID,
              let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        let profile = profiles[index]
        CredentialStore.forget(account: profile.account, target: profile.connection)
        CredentialStore.forgetSession(account: profile.account, target: profile.connection)
        profiles[index].remembersPassword = false
        Preferences.rememberPassword = false
        persistProfiles()
    }

    func consumeDisconnectionMessage() -> String? {
        defer { disconnectionMessage = nil }
        return disconnectionMessage
    }

    /// To be called after an automatic reconnection following an expiration, when the
    /// sign-in screen was only an invisible transient state.
    func publishAutomaticReconnectionNotice() {
        reconnectionNotice = String(
            localized: "session.reconnected.description"
        )
    }

    func dismissReconnectionNotice() {
        reconnectionNotice = nil
    }

    /// Resets the state (after logout or session expiration).
    func clear() {
        generation += 1
        connectionTarget = nil
        self.endpoint = nil
        self.client = nil
        capabilities = DSMCapabilities()
        activeProfileID = nil
        reconnectionNotice = nil
    }

    private func expireSession() {
        disconnectionMessage = DSMError.sessionExpired.errorDescription
        forgetStoredSession()
        clear()
    }

    private func registerProfile(
        target: NASConnectionTarget,
        account: String,
        remembersPassword: Bool
    ) {
        let existingID = requestedProfileID ?? profiles.first {
            $0.connection == target && $0.account == account
        }?.id

        if let existingID,
           let index = profiles.firstIndex(where: { $0.id == existingID }) {
            profiles[index].connection = target
            profiles[index].account = account
            profiles[index].remembersPassword = remembersPassword
            activeProfileID = existingID
        } else {
            let profile = NASProfile(
                name: target.defaultProfileName,
                connection: target,
                account: account,
                remembersPassword: remembersPassword
            )
            profiles.append(profile)
            activeProfileID = profile.id
        }

        requestedProfileID = nil
        requestsBlankConnection = false
        Preferences.selectedNASProfileID = activeProfileID
        persistProfiles()
    }

    private func persistProfiles() {
        profiles.sort {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        Preferences.nasProfiles = profiles
    }

    private func persistLegacyConnectionPreferences(for profile: NASProfile) {
        if let endpoint = profile.connection.directEndpoint {
            Preferences.lastHost = endpoint.host
            Preferences.lastPort = endpoint.port
            Preferences.lastUseHTTPS = endpoint.useHTTPS
        } else {
            Preferences.lastHost = ""
            Preferences.lastPort = nil
            Preferences.lastUseHTTPS = true
        }
        Preferences.lastAccount = profile.account
        Preferences.rememberPassword = profile.remembersPassword
    }
}
