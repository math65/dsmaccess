//
//  SessionStore.swift
//  dsmaccess
//
//  État de session partagé de l'app : client connecté, SID courant, hôte.
//  Observé par RootView pour basculer entre l'écran de connexion et le contenu.
//

import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    /// Endpoint du NAS actuellement connecté (nil si déconnecté).
    private(set) var endpoint: DSMEndpoint?
    /// Identifiant de session DSM (nil si déconnecté).
    private(set) var sid: String?
    /// Client réseau réutilisable par les écrans (infos, plus tard fichiers/utilisateurs…).
    private(set) var client: DSMClientProtocol?
    /// API réellement exposées par le DSM et ses paquets installés.
    private(set) var capabilities = DSMCapabilities()

    var isLoggedIn: Bool { sid != nil }

    /// Enregistre une session ouverte après un login réussi.
    func establish(
        endpoint: DSMEndpoint,
        sid: String,
        client: DSMClientProtocol,
        capabilities: DSMCapabilities
    ) {
        self.endpoint = endpoint
        self.sid = sid
        self.client = client
        self.capabilities = capabilities
    }

    /// Réinitialise l'état (après logout ou expiration de session).
    func clear() {
        self.endpoint = nil
        self.sid = nil
        self.client = nil
        capabilities = DSMCapabilities()
    }
}
