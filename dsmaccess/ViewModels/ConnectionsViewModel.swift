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
            // La session courante d'abord : c'est celle que l'utilisateur cherche à
            // reconnaître avant d'agir sur une autre.
            connections = result.sorted { lhs, rhs in
                if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
                return (lhs.openedAt ?? .distantPast) > (rhs.openedAt ?? .distantPast)
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

    /// « SMB3 depuis 192.168.1.10, ouverte le 29 juillet à 18:02 ». Le protocole d'abord :
    /// c'est ce qui distingue deux connexions d'une même machine.
    func detailText(for connection: NASConnection) -> String {
        let type = connection.type ?? String(localized: "Protocole inconnu")
        let address = connection.address ?? String(localized: "adresse inconnue")
        guard let openedAt = connection.openedAt else {
            return String(localized: "\(type) depuis \(address)")
        }
        let moment = openedAt.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "\(type) depuis \(address), ouverte le \(moment)")
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(connections.count) connexions ouvertes")
    }
}
