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

    func load() async {
        guard let client = session.client, let sid = session.sid else {
            session.clear()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            info = try await client.storageInfo(sid: sid)
        } catch {
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Résumé annoncé à VoiceOver une fois chargé.
    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(volumes.count) volumes, \(disks.count) disques")
    }
}
