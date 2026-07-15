//
//  StorageViewModel.swift
//  dsmaccess
//
//  Charge et expose l'état du stockage (volumes + disques) du NAS.
//

import Foundation
import Observation

@MainActor
@Observable
final class StorageViewModel {
    private(set) var info: StorageInfo?
    private(set) var isLoading = false
    var errorMessage: String?

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    var volumes: [Volume] {
        (info?.volumes ?? []).sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }
    var disks: [Disk] {
        (info?.disks ?? []).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }
    var pools: [StoragePool] {
        (info?.storagePools ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            info = try await session.withClient { try await $0.storageInfo() }
        } catch {
            // Une annulation (vue quittée / requête remplacée) n'est pas un échec : on l'ignore,
            // sinon un faux « impossible de joindre le NAS » s'affiche alors que les données arrivent.
            if !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    /// Résumé annoncé à VoiceOver une fois chargé.
    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(volumes.count) volumes, \(disks.count) disques")
    }
}
