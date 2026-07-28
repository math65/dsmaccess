//
//  SessionStore.swift
//  dsmaccess
//
//  État de session partagé de l'app : client connecté, capacités et hôte.
//  Observé par RootView pour basculer entre l'écran de connexion et le contenu.
//

import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    /// Endpoint du NAS actuellement connecté (nil si déconnecté).
    private(set) var endpoint: DSMEndpoint?
    /// Identité stable ayant produit l'endpoint courant.
    private(set) var connectionTarget: NASConnectionTarget?
    /// Le client possède la session DSM et reste la seule source du SID et du SynoToken.
    private var client: DSMClientProtocol?
    private var generation = 0
    /// API réellement exposées par le DSM et ses paquets installés.
    private(set) var capabilities = DSMCapabilities()
    /// NAS enregistrés. Les mots de passe restent exclusivement dans le Trousseau.
    private(set) var profiles: [NASProfile]
    private(set) var activeProfileID: UUID?
    private var requestedProfileID: UUID?
    private var requestsBlankConnection = false

    /// Motif d'une déconnexion imposée, consommé par l'écran de connexion.
    private(set) var disconnectionMessage: String?

    /// Avis présenté dans l'interface connectée quand la session a été rétablie
    /// automatiquement après une expiration : sans lui, l'utilisateur revient sur la vue
    /// d'ensemble sans savoir que son opération a été interrompue.
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

    /// Enregistre une session ouverte après un login réussi.
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

    /// Exécute toute opération avec le client de la session et invalide l'ensemble de
    /// l'état si DSM signale une expiration. Les vues ne manipulent jamais le SID.
    func withClient<Value>(
        _ operation: (DSMClientProtocol) async throws -> Value
    ) async throws -> Value {
        guard let client else {
            // Une tâche appartenant à une vue disparue peut arriver ici après une
            // déconnexion volontaire. Elle ne doit pas transformer ce logout en
            // fausse expiration de session sur l'écran de connexion.
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

    /// Demande à l'hôte s'il a fini de démarrer, sans passer par `withClient` : pendant un
    /// redémarrage il n'y a plus de session, et la garde de génération rejetterait la réponse.
    /// Répond faux si le NAS est injoignable — c'est le cas attendu tant qu'il redémarre.
    func isNASBackOnline() async -> Bool {
        guard let client else { return false }
        return await client.isNASBackOnline()
    }

    func logout() async {
        let activeClient = client
        clear()
        try? await activeClient?.logout()
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
        profiles[index].remembersPassword = false
        Preferences.rememberPassword = false
        persistProfiles()
    }

    func consumeDisconnectionMessage() -> String? {
        defer { disconnectionMessage = nil }
        return disconnectionMessage
    }

    /// À appeler après une reconnexion automatique consécutive à une expiration,
    /// quand l'écran de connexion n'a été qu'un état transitoire invisible.
    func publishAutomaticReconnectionNotice() {
        reconnectionNotice = String(
            localized: "La session avait expiré et la connexion a été rétablie automatiquement. Si une opération était en cours, elle a été interrompue : vérifiez son état avant de la relancer."
        )
    }

    func dismissReconnectionNotice() {
        reconnectionNotice = nil
    }

    /// Réinitialise l'état (après logout ou expiration de session).
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
