//
//  FinderUploadPlan.swift
//  dsmaccess
//
//  Expansion locale d'une sélection du Finder en plan d'envoi : fichiers avec
//  leur dossier relatif, arborescence de dossiers à recréer sur le NAS.
//

import Foundation

/// L'API d'envoi de File Station traite un fichier à la fois : un dossier collé
/// ou choisi dans le Finder est donc développé côté Mac avant l'envoi.
struct FinderUploadPlan: Equatable, Sendable {
    struct File: Equatable, Sendable {
        let source: URL
        /// Chemin du dossier relatif à la destination (« Vacances/2024 »),
        /// ou `nil` pour un fichier envoyé directement dans la destination.
        let relativeFolder: String?

        func destinationFolder(under parent: String) -> String {
            relativeFolder.map { "\(parent)/\($0)" } ?? parent
        }
    }

    var files: [File] = []
    /// Tous les dossiers de l'arborescence, vides compris, en chemins relatifs.
    var folders: [String] = []
    /// Éléments que l'énumération locale n'a pas pu lire : l'envoi ne doit pas
    /// les passer sous silence.
    var unreadableItems = 0

    func folderCreations(under parent: String) -> [FileStationFolderCreation] {
        folders.map { relative in
            var components = relative.split(separator: "/").map(String.init)
            let name = components.removeLast()
            let parentPath = ([parent] + components).joined(separator: "/")
            return FileStationFolderCreation(parentPath: parentPath, name: name)
        }
    }

    /// L'énumération lit le disque : elle reste hors du MainActor.
    @concurrent
    static func make(from urls: [URL]) async -> FinderUploadPlan {
        var plan = FinderUploadPlan()
        let fileManager = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                plan.unreadableItems += 1
                continue
            }
            if isDirectory.boolValue {
                plan.add(directory: url, fileManager: fileManager)
            } else {
                plan.files.append(File(source: url, relativeFolder: nil))
            }
        }
        plan.files.sort {
            ($0.relativeFolder ?? "", $0.source.lastPathComponent)
                < ($1.relativeFolder ?? "", $1.source.lastPathComponent)
        }
        plan.folders.sort()
        return plan
    }

    private mutating func add(directory url: URL, fileManager: FileManager) {
        let root = url.lastPathComponent
        folders.append(root)
        var unreadable = 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { _, _ in
                unreadable += 1
                return true
            }
        ) else {
            unreadableItems += 1
            return
        }
        let basePath = url.path + "/"
        for case let descendant as URL in enumerator {
            // Métadonnée du Finder sans valeur sur le NAS.
            if descendant.lastPathComponent == ".DS_Store" { continue }
            guard descendant.path.hasPrefix(basePath) else {
                unreadable += 1
                continue
            }
            let relative = root + "/" + descendant.path.dropFirst(basePath.count)
            if (try? descendant.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                folders.append(relative)
            } else {
                let parent = relative.split(separator: "/").dropLast().joined(separator: "/")
                files.append(File(source: descendant, relativeFolder: parent))
            }
        }
        unreadableItems += unreadable
    }
}
