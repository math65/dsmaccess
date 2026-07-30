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
    private var loadGeneration = 0

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
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { try await $0.storageInfo() }
            guard generation == loadGeneration else { return }
            info = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Résumé annoncé à VoiceOver une fois chargé.
    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "storage.summary.counts", defaultValue: "\(volumes.count) volumes, \(disks.count) disks")
    }
}
