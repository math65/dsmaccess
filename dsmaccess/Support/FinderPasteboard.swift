//
//  FinderPasteboard.swift
//  dsmaccess
//
//  Bridge between the Files module and the system pasteboard: detection of Finder
//  files to paste, file promises for drag and drop.
//

import AppKit
import UniformTypeIdentifiers

/// ⌘C and ⌘X claim the system pasteboard on top of the internal pasteboard
/// (NAS→NAS copy); `intent` then settles ⌘V according to the rule
/// "the last copy wins".
enum FinderPasteboard {
    /// What Paste must do depending on the contents of both pasteboards.
    enum PasteIntent: Equatable {
        case uploadFinderFiles([URL])
        case pasteInternalClipboard
        case nothing
    }

    /// The pasteboard's `changeCount` after our last write, so our own copy can be
    /// told apart from a copy made in the Finder.
    private static var lastOwnChangeCount: Int?

    /// Promise delegates of a drag being prepared: the table builds them row by row
    /// before the drag session starts.
    private static var pendingDragDelegates = [FileStationFilePromiseDelegate]()
    /// Delegates of the last drag session. The Finder honours promises after the
    /// session has ended; they are only released at the next drag, the way a ⌘C's
    /// delegates are released at the next copy.
    private static var activeDragDelegates = [FileStationFilePromiseDelegate]()

    /// File promise for a row dragged out of the app: the download only starts if
    /// the item is actually dropped.
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

    /// An internal copy or cut claims the pasteboard: without that, ⌘V after
    /// "copy in the Finder then ⌘C or ⌘X here" would send the Finder's files
    /// instead of pasting the internal selection. Since the Finder does not
    /// honour promises on paste, there is nothing useful to write there:
    /// promises only serve drag and drop.
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

/// Honours a file promise: when the Finder pastes, it supplies the destination URL
/// (covered by its own sandbox) and the download starts then.
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
        // The promise queue is a background one; the session and the transfer
        // tracking live on the MainActor.
        Task { @MainActor in
            guard let viewModel else {
                completionHandler(FilePromiseError(
                    message: String(
                        localized: "finder.paste.session.error"
                    )
                ))
                return
            }
            VoiceOver.announce(
                String(localized: "finder.paste.download.progress"),
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

/// Error handed to the Finder when a promise cannot be honoured; it displays the
/// description in its own alert.
private struct FilePromiseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
