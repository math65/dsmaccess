import Foundation
import Testing
@testable import dsmaccess

struct DownloadDestinationTests {
    private let directory = URL(filePath: "/Users/example/Downloads", directoryHint: .isDirectory)

    @Test func keepsAnOrdinaryName() {
        #expect(FileStationItem.localFileName("Rapport 2026 (final).pdf") == "Rapport 2026 (final).pdf")
    }

    @Test func aSlashCannotReachAnotherFolder() {
        let name = FileStationItem.localFileName("../../Library/evil.plist")
        #expect(!name.contains("/"))
        #expect(URL(filePath: "/tmp/x").appendingPathComponent(name).deletingLastPathComponent().path == "/tmp/x")
    }

    @Test func dotNamesNeverNameAFolder() {
        #expect(FileStationItem.localFileName("..") != "..")
        #expect(FileStationItem.localFileName(".") != ".")
        #expect(!FileStationItem.localFileName("").isEmpty)
    }

    @Test func keepsAFreeName() {
        let destination = FileBrowserViewModel.availableDestination(
            for: "photo.jpg",
            in: directory,
            excluding: [],
            fileExists: { _ in false }
        )
        #expect(destination.lastPathComponent == "photo.jpg")
    }

    @Test func numbersANameAlreadyOnDisk() {
        let destination = FileBrowserViewModel.availableDestination(
            for: "photo.jpg",
            in: directory,
            excluding: [],
            fileExists: { $0.lastPathComponent == "photo.jpg" }
        )
        #expect(destination.lastPathComponent == "photo 2.jpg")
    }

    @Test func twoItemsOfTheSameNameDoNotOverwriteEachOther() {
        let destination = FileBrowserViewModel.availableDestination(
            for: "Photo.JPG",
            in: directory,
            excluding: ["photo.jpg", "photo 2.jpg"],
            fileExists: { _ in false }
        )
        #expect(destination.lastPathComponent == "Photo 3.JPG")
    }

    @Test func numbersANameWithoutExtension() {
        let destination = FileBrowserViewModel.availableDestination(
            for: "README",
            in: directory,
            excluding: ["readme"],
            fileExists: { _ in false }
        )
        #expect(destination.lastPathComponent == "README 2")
    }
}
