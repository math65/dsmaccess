//
//  ConnectionsViewModel.swift
//  dsmaccess
//
//  Onglet Connexions du moniteur de ressources : qui est connecté au NAS, depuis où et
//  par quel protocole. Lecture seule pour l'instant — DSM sait aussi couper une session
//  (`kick_connection`), action destructive qui reste à cadrer.
//

import Foundation
import Observation

@MainActor
@Observable
final class ConnectionsViewModel {
    private(set) var connections: [NASConnection] = []
    private(set) var isLoading = false
    var errorMessage: String?

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
            // Le tri visible appartient au tableau ; ici, seul un ordre de départ stable
            // est fixé, de la session la plus récente à la plus ancienne.
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

    /// Horodatage rendu dans la langue du Mac. Un tiret quand DSM a envoyé une forme que
    /// nous n'avons pas su lire : la connexion reste listée, sans date inventée.
    func openedAtText(for connection: NASConnection) -> String {
        guard let openedAt = connection.openedAt else { return "—" }
        return openedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(connections.count) connexions ouvertes")
    }
}
