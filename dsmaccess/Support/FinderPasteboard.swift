//
//  FinderPasteboard.swift
//  dsmaccess
//
//  Pont entre le module Fichiers et le presse-papiers système : détection des
//  fichiers du Finder à coller, promesses de fichiers pour le glisser-déposer.
//

import AppKit
import UniformTypeIdentifiers

/// ⌘C et ⌘X réclament le presse-papiers système en plus du presse-papiers
/// interne (copie NAS→NAS) ; `intent` départage ensuite ⌘V selon la règle
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

    /// Délégués des promesses d'un drag en cours de préparation : la table les
    /// fabrique ligne par ligne avant que la session de drag ne commence.
    private static var pendingDragDelegates = [FileStationFilePromiseDelegate]()
    /// Délégués de la dernière session de drag. Le Finder honore les promesses
    /// après la fin de la session ; ils ne sont libérés qu'au drag suivant,
    /// comme les délégués d'un ⌘C le sont à la copie suivante.
    private static var activeDragDelegates = [FileStationFilePromiseDelegate]()

    /// Promesse de fichier pour une ligne glissée hors de l'app : le
    /// téléchargement ne démarre que si l'élément est réellement déposé.
    static func dragProvider(
        for item: FileStationItem,
        viewModel: FileBrowserViewModel
    ) -> NSFilePromiseProvider {
        let delegate = FileStationFilePromiseDelegate(item: item, viewModel: viewModel)
        pendingDragDelegates.append(delegate)
        return NSFilePromiseProvider(fileType: promisedFileType(for: item), delegate: delegate)
    }

    static func dragSessionWillBegin() {
        activeDragDelegates = pendingDragDelegates
        pendingDragDelegates = []
    }

    /// Une copie ou un couper interne réclame le presse-papiers : sans cela,
    /// ⌘V après « copie dans le Finder puis ⌘C ou ⌘X ici » enverrait les
    /// fichiers du Finder au lieu de coller la sélection interne. Le Finder
    /// n'honorant pas les promesses au collage, il n'y a rien d'utile à y
    /// écrire : les promesses ne servent qu'au glisser-déposer.
    static func claimForInternalClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
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
                        localized: "Le transfert vers le Finder a échoué : la session NAS n’est plus disponible."
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
