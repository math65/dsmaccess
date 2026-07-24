//
//  FinderPasteboard.swift
//  dsmaccess
//
//  Pont entre le module Fichiers et le presse-papiers système : copie vers le
//  Finder par promesses de fichiers, détection des fichiers du Finder à coller.
//

import AppKit
import UniformTypeIdentifiers

/// ⌘C alimente à la fois le presse-papiers interne (copie NAS→NAS) et le
/// presse-papiers système ; `intent` départage ensuite ⌘V selon la règle
/// « le dernier copier gagne ».
enum FinderPasteboard {
    /// Ce que Coller doit faire selon le contenu des deux presse-papiers.
    enum PasteIntent: Equatable {
        case uploadFinderFiles([URL])
        case pasteInternalClipboard
        case nothing
    }

    /// `changeCount` du presse-papiers après notre dernière écriture, pour
    /// distinguer notre propre copie d'une copie faite dans le Finder.
    private static var lastOwnChangeCount: Int?
    /// `NSFilePromiseProvider` ne retient pas son délégué ; ils sont conservés
    /// ici jusqu'à la prochaine écriture, le temps que le Finder honore les promesses.
    private static var activeDelegates = [FileStationFilePromiseDelegate]()

    /// Remplace le presse-papiers système par une promesse de fichier par élément :
    /// chaque fichier sous son propre nom, chaque dossier en archive ZIP.
    static func write(items: [FileStationItem], viewModel: FileBrowserViewModel) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let delegates = items.map { FileStationFilePromiseDelegate(item: $0, viewModel: viewModel) }
        let providers = delegates.map {
            NSFilePromiseProvider(fileType: promisedFileType(for: $0.item), delegate: $0)
        }
        pasteboard.writeObjects(providers)
        activeDelegates = delegates
        lastOwnChangeCount = pasteboard.changeCount
    }

    /// Un couper interne réclame le presse-papiers : sans cela, ⌘V après
    /// « copie dans le Finder puis ⌘X ici » enverrait les fichiers du Finder
    /// au lieu de déplacer les éléments coupés.
    static func claimForInternalCut() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        activeDelegates = []
        lastOwnChangeCount = pasteboard.changeCount
    }

    static func currentIntent(hasInternalClipboard: Bool) -> PasteIntent {
        let pasteboard = NSPasteboard.general
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return intent(
            hasInternalClipboard: hasInternalClipboard,
            changeCount: pasteboard.changeCount,
            lastOwnChangeCount: lastOwnChangeCount,
            fileURLs: urls
        )
    }

    nonisolated static func intent(
        hasInternalClipboard: Bool,
        changeCount: Int,
        lastOwnChangeCount: Int?,
        fileURLs: [URL]
    ) -> PasteIntent {
        if changeCount != lastOwnChangeCount, !fileURLs.isEmpty {
            return .uploadFinderFiles(fileURLs)
        }
        return hasInternalClipboard ? .pasteInternalClipboard : .nothing
    }

    nonisolated static func promisedFileType(for item: FileStationItem) -> String {
        if item.isdir { return UTType.zip.identifier }
        let ext = (item.name as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else {
            return UTType.data.identifier
        }
        return type.identifier
    }
}

/// Honore une promesse de fichier : quand le Finder colle, il fournit l'URL de
/// destination (couverte par son propre sandbox) et le téléchargement démarre alors.
final class FileStationFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    nonisolated let item: FileStationItem
    private weak var viewModel: FileBrowserViewModel?

    init(item: FileStationItem, viewModel: FileBrowserViewModel) {
        self.item = item
        self.viewModel = viewModel
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        item.promisedFileName
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        // La queue des promesses est en arrière-plan ; la session et le suivi
        // des transferts vivent sur le MainActor.
        Task { @MainActor in
            guard let viewModel else {
                completionHandler(FilePromiseError(
                    message: String(
                        localized: "Le collage dans le Finder a échoué : la session NAS n’est plus disponible."
                    )
                ))
                return
            }
            VoiceOver.announce(
                String(localized: "Téléchargement pour le Finder en cours…"),
                category: .progress,
                priority: .low
            )
            let outcome = await viewModel.downloadForFinderPromise(item, to: url)
            VoiceOver.announce(outcome, priority: .high)
            switch outcome {
            case .success:
                completionHandler(nil)
            case .cancelled:
                completionHandler(CocoaError(.userCancelled))
            case .failure(let message):
                completionHandler(FilePromiseError(message: message))
            }
        }
    }
}

/// Erreur remise au Finder quand une promesse ne peut pas être honorée ;
/// il en affiche la description dans sa propre alerte.
private struct FilePromiseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
