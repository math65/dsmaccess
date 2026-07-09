//
//  FileBrowserViewModel.swift
//  dsmaccess
//
//  État du navigateur File Station en mode « drill-in » façon Finder : une pile de
//  niveaux (racine = dossiers partagés, puis un dossier par descente). Ouvrir empile
//  et charge le contenu ; remonter dépile. Le contenu courant alimente le NSTableView.
//

import Foundation
import Observation

@MainActor
@Observable
final class FileBrowserViewModel {
    /// Un niveau de la pile de navigation. `path == nil` désigne la racine (dossiers partagés).
    struct Level: Equatable {
        let name: String
        let path: String?
    }

    private(set) var stack: [Level]
    private(set) var items: [FileStationItem] = []
    private(set) var isLoading = false
    private(set) var isDownloading = false
    var errorMessage: String?

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        self.stack = [Level(name: String(localized: "Fichiers"), path: nil)]
    }

    var currentLevel: Level { stack.last ?? Level(name: String(localized: "Fichiers"), path: nil) }
    var title: String { currentLevel.name }
    var canGoUp: Bool { stack.count > 1 }
    /// Vrai à l'intérieur d'un partage (actions d'écriture permises) ; faux à la racine des
    /// dossiers partagés, où l'on ne peut ni créer ni renommer/supprimer.
    var canWrite: Bool { currentLevel.path != nil }

    /// Fil d'Ariane lu par VoiceOver : « Fichiers ▸ photo ▸ 2024 ».
    var breadcrumb: String { stack.map(\.name).joined(separator: " ▸ ") }

    /// Charge le contenu du niveau courant (partages à la racine, sinon contenu du dossier).
    func loadCurrent() async {
        guard let client = session.client, let sid = session.sid else {
            session.clear()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let result: [FileStationItem]
            if let path = currentLevel.path {
                result = try await client.list(folderPath: path, sid: sid)
            } else {
                result = try await client.listShares(sid: sid)
            }
            items = result.sortedForBrowsing()
        } catch {
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Entre dans un dossier (ignore les fichiers en navigation seule).
    func open(_ item: FileStationItem) async {
        guard item.isdir else { return }
        stack.append(Level(name: item.name, path: item.path))
        await loadCurrent()
    }

    /// Remonte au dossier parent.
    func goUp() async {
        guard canGoUp else { return }
        stack.removeLast()
        await loadCurrent()
    }

    /// Télécharge `item` vers `destination` (un dossier arrive en ZIP). Renvoie le message
    /// à annoncer à VoiceOver (succès ou échec).
    func downloadItem(_ item: FileStationItem, to destination: URL) async -> String {
        guard let client = session.client, let sid = session.sid else {
            session.clear()
            return String(localized: "Session expirée.")
        }
        isDownloading = true
        defer { isDownloading = false }
        do {
            try await client.downloadFile(path: item.path, sid: sid, to: destination)
            return String(localized: "Téléchargement terminé : \(item.name)")
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec du téléchargement : \(reason)")
        }
    }

    /// Nom de fichier proposé dans le panneau d'enregistrement (dossier → `nom.zip`).
    func suggestedFilename(for item: FileStationItem) -> String {
        item.isdir ? "\(item.name).zip" : item.name
    }

    // MARK: - Actions d'écriture (renvoient le message à annoncer à VoiceOver)

    /// Crée un dossier `name` dans le dossier courant.
    func createFolder(named name: String) async -> String {
        guard let client = session.client, let sid = session.sid, let parent = currentLevel.path else {
            return String(localized: "Impossible de créer le dossier ici.")
        }
        do {
            try await client.createFolder(in: parent, name: name, sid: sid)
            await loadCurrent()
            return String(localized: "Dossier créé : \(name)")
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec de la création : \(reason)")
        }
    }

    /// Renomme `item` en `name`.
    func rename(_ item: FileStationItem, to name: String) async -> String {
        guard let client = session.client, let sid = session.sid else {
            return String(localized: "Session expirée.")
        }
        do {
            try await client.rename(path: item.path, to: name, sid: sid)
            await loadCurrent()
            return String(localized: "Renommé en : \(name)")
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec du renommage : \(reason)")
        }
    }

    /// Supprime `item`.
    func delete(_ item: FileStationItem) async -> String {
        guard let client = session.client, let sid = session.sid else {
            return String(localized: "Session expirée.")
        }
        do {
            try await client.delete(path: item.path, sid: sid)
            await loadCurrent()
            return String(localized: "Supprimé : \(item.name)")
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec de la suppression : \(reason)")
        }
    }

    /// Envoie les fichiers `fileURLs` dans le dossier courant. Renvoie le message VoiceOver.
    func upload(fileURLs: [URL]) async -> String {
        guard let client = session.client, let sid = session.sid, let parent = currentLevel.path else {
            return String(localized: "Impossible d'envoyer ici.")
        }
        var sent = 0
        var firstFailure: String?
        for url in fileURLs {
            do {
                try await client.upload(fileURL: url, to: parent, sid: sid)
                sent += 1
            } catch {
                if firstFailure == nil {
                    firstFailure = (error as? DSMError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        await loadCurrent()
        let failed = fileURLs.count - sent
        if failed > 0, let firstFailure {
            return String(localized: "\(sent) envoyés, \(failed) en échec : \(firstFailure)")
        }
        switch sent {
        case 0: return String(localized: "Impossible d'envoyer ici.")
        case 1: return String(localized: "Fichier envoyé : \(fileURLs.first?.lastPathComponent ?? "")")
        default: return String(localized: "\(sent) fichiers envoyés")
        }
    }

    /// Résumé annoncé à VoiceOver après un chargement / une navigation.
    var summary: String {
        if let errorMessage { return errorMessage }
        let count: String
        switch items.count {
        case 0: count = String(localized: "Dossier vide")
        case 1: count = String(localized: "1 élément")
        default: count = String(localized: "\(items.count) éléments")
        }
        return "\(title), \(count)"
    }
}
