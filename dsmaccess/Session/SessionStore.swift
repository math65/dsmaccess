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
    /// Le client possède la session DSM et reste la seule source du SID et du SynoToken.
    private var client: DSMClientProtocol?
    /// API réellement exposées par le DSM et ses paquets installés.
    private(set) var capabilities = DSMCapabilities()

    /// Motif d'une déconnexion imposée, consommé par l'écran de connexion.
    private(set) var disconnectionMessage: String?

    var isLoggedIn: Bool { client != nil }

    /// Enregistre une session ouverte après un login réussi.
    func establish(
        endpoint: DSMEndpoint,
        client: DSMClientProtocol,
        capabilities: DSMCapabilities
    ) {
        self.endpoint = endpoint
        self.client = client
        self.capabilities = capabilities
        disconnectionMessage = nil
    }

    /// Exécute toute opération avec le client de la session et invalide l'ensemble de
    /// l'état si DSM signale une expiration. Les vues ne manipulent jamais le SID.
    func withClient<Value>(
        _ operation: (DSMClientProtocol) async throws -> Value
    ) async throws -> Value {
        guard let client else {
            expireSession()
            throw DSMError.sessionExpired
        }
        do {
            return try await operation(client)
        } catch DSMError.sessionExpired {
            expireSession()
            throw DSMError.sessionExpired
        }
    }

    func logout() async {
        let activeClient = client
        clear()
        try? await activeClient?.logout()
    }

    func consumeDisconnectionMessage() -> String? {
        defer { disconnectionMessage = nil }
        return disconnectionMessage
    }

    /// Réinitialise l'état (après logout ou expiration de session).
    func clear() {
        self.endpoint = nil
        self.client = nil
        capabilities = DSMCapabilities()
    }

    private func expireSession() {
        disconnectionMessage = DSMError.sessionExpired.errorDescription
        clear()
    }
}
