//
//  NetworkSettingsViewModel.swift
//  dsmaccess
//
//  Sous-module « Réseau et identité » du Panneau de configuration : charge la configuration
//  réseau du NAS (SYNO.Core.Network). Lecture seule pour l'instant (le renommage viendra).
//

import Foundation
import Observation

@MainActor
@Observable
final class NetworkSettingsViewModel {
    private(set) var info: NetworkInfo?
    private(set) var isLoading = false
    var errorMessage: String?

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        guard let client = session.client, let sid = session.sid else {
            session.clear()
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            info = try await client.networkInfo(sid: sid)
        } catch {
            // Une annulation (vue quittée / requête remplacée) n'est pas un échec : on l'ignore.
            if !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Phrase annoncée à VoiceOver en fin de chargement.
    var summary: String {
        if let errorMessage { return errorMessage }
        guard let info else { return String(localized: "Configuration réseau indisponible") }
        if let name = info.serverName, !name.isEmpty {
            return String(localized: "Serveur \(name)")
        }
        return String(localized: "Configuration réseau chargée")
    }
}
