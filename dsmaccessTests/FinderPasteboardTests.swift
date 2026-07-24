import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct FinderPasteboardTests {
    private func item(name: String, isdir: Bool) throws -> FileStationItem {
        try JSONDecoder().decode(
            FileStationItem.self,
            from: Data(#"{"name":"\#(name)","path":"/partage/\#(name)","isdir":\#(isdir)}"#.utf8)
        )
    }

    @Test func finderFilesWinOverInternalClipboard() {
        let urls = [URL(fileURLWithPath: "/Users/test/rapport.pdf")]
        let intent = FinderPasteboard.intent(
            hasInternalClipboard: true,
            changeCount: 12,
            lastOwnChangeCount: 9,
            fileURLs: urls
        )

        #expect(intent == .uploadFinderFiles(urls))
    }

    @Test func ownPasteboardWriteNeverTriggersUpload() {
        let intent = FinderPasteboard.intent(
            hasInternalClipboard: true,
            changeCount: 12,
            lastOwnChangeCount: 12,
            fileURLs: [URL(fileURLWithPath: "/Users/test/rapport.pdf")]
        )

        #expect(intent == .pasteInternalClipboard)
    }

    @Test func foreignPasteboardWithoutFilesFallsBackToInternalClipboard() {
        let intent = FinderPasteboard.intent(
            hasInternalClipboard: true,
            changeCount: 12,
            lastOwnChangeCount: 9,
            fileURLs: []
        )

        #expect(intent == .pasteInternalClipboard)
    }

    @Test func nothingToPasteWhenBothClipboardsAreEmpty() {
        let intent = FinderPasteboard.intent(
            hasInternalClipboard: false,
            changeCount: 12,
            lastOwnChangeCount: nil,
            fileURLs: []
        )

        #expect(intent == .nothing)
    }

    @Test func finderFilesUploadEvenBeforeAnyOwnWrite() {
        let urls = [URL(fileURLWithPath: "/Users/test/photo.jpg")]
        let intent = FinderPasteboard.intent(
            hasInternalClipboard: false,
            changeCount: 3,
            lastOwnChangeCount: nil,
            fileURLs: urls
        )

        #expect(intent == .uploadFinderFiles(urls))
    }

    @Test func promisedFileNameKeepsFilesAndZipsFolders() throws {
        let file = try item(name: "rapport.pdf", isdir: false)
        let folder = try item(name: "Vacances", isdir: true)

        #expect(file.promisedFileName == "rapport.pdf")
        #expect(folder.promisedFileName == "Vacances.zip")
    }

    @Test func promisedFileTypeMatchesItemKind() throws {
        let folder = try item(name: "Vacances", isdir: true)
        let pdf = try item(name: "rapport.pdf", isdir: false)
        let noExtension = try item(name: "LISEZMOI", isdir: false)

        #expect(FinderPasteboard.promisedFileType(for: folder) == "public.zip-archive")
        #expect(FinderPasteboard.promisedFileType(for: pdf) == "com.adobe.pdf")
        #expect(FinderPasteboard.promisedFileType(for: noExtension) == "public.data")
    }
}
