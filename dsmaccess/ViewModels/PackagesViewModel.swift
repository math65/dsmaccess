//
//  PackagesViewModel.swift
//  dsmaccess
//
//  Charge la liste des paquets installés (SYNO.Core.Package). Lecture seule pour cette
//  première tranche ; la mise à jour viendra ensuite. Écrit aussi la réponse brute dans
//  un fichier (diagnostic temporaire) pour caler les vrais noms de champs de l'API.
//

import Foundation
import Observation

@MainActor
@Observable
final class PackagesViewModel {
    private(set) var packages: [PackageInfo] = []
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
        do {
            packages = try await client.listPackages(sid: sid).sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        } catch {
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Résumé annoncé à VoiceOver une fois chargé.
    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(packages.count) paquets installés")
    }
}
