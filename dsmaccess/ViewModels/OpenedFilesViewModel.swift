//
//  OpenedFilesViewModel.swift
//  dsmaccess
//
//  Onglet « Fichiers ouverts » du moniteur de ressources : quels fichiers le NAS tient
//  ouverts en ce moment, et pour qui. Utile avant de démonter un volume ou d'arrêter un
//  service — et pour répondre à « qui bloque ce fichier ? ».
//

import Foundation
import Observation

@MainActor
@Observable
final class OpenedFilesViewModel {
    /// Un NAS actif peut tenir des centaines de fichiers ouverts. La page demandée est large
    /// mais bornée, et l'écran dit ce qu'il ne montre pas plutôt que de tronquer en silence.
    static let pageLimit = 500

    private(set) var files: [OpenedFile] = []
    /// Total renvoyé par le NAS, qui peut dépasser ce qui est chargé.
    private(set) var totalCount = 0
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
        if files.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page = try await session.withClient {
                try await $0.openedFiles(limit: Self.pageLimit)
            }
            guard generation == loadGeneration else { return }
            // Ordre de départ stable, par service puis par chemin : le NAS renvoie les
            // fichiers dans un ordre qui lui est propre et qui change d'un appel à l'autre.
            // Le tri visible reste celui que l'utilisateur choisit sur les en-têtes.
            files = page.files.sorted { lhs, rhs in
                let leftService = lhs.sortableService
                let rightService = rhs.sortableService
                if leftService != rightService {
                    return leftService.localizedStandardCompare(rightService) == .orderedAscending
                }
                return lhs.sortableName.localizedStandardCompare(rhs.sortableName) == .orderedAscending
            }
            totalCount = page.total ?? files.count
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    /// Un service local du NAS n'a ni compte ni machine d'origine : le tiret dit l'absence,
    /// là où répéter le nom du service ferait croire à une donnée.
    func accountText(for file: OpenedFile) -> String { file.account ?? "—" }
    func hostText(for file: OpenedFile) -> String { file.host ?? "—" }
    func serviceText(for file: OpenedFile) -> String {
        file.service ?? String(localized: "Service inconnu")
    }
    func folderText(for file: OpenedFile) -> String { file.folder ?? "—" }

    /// Vrai quand le NAS en tient plus que ce qui a été chargé.
    var isTruncated: Bool { totalCount > files.count }

    var summary: String {
        if let errorMessage { return errorMessage }
        if isTruncated {
            return String(localized: "\(files.count) fichiers affichés sur \(totalCount) ouverts")
        }
        return String(localized: "\(files.count) fichiers ouverts")
    }
}
