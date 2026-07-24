import Foundation
import Testing
@testable import dsmaccess

struct FinderUploadPlanTests {
    /// Crée une arborescence temporaire réelle : l'énumération du plan repose
    /// sur FileManager, pas sur des doublures.
    private func makeTemporaryTree(
        files: [String],
        folders: [String] = []
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderUploadPlanTests-\(UUID().uuidString)", isDirectory: true)
        for folder in folders {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("contenu".utf8).write(to: url)
        }
        return root
    }

    @Test func flatFilesUploadDirectlyIntoDestination() async throws {
        let root = try makeTemporaryTree(files: ["rapport.pdf", "photo.jpg"])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = await FinderUploadPlan.make(from: [
            root.appendingPathComponent("rapport.pdf"),
            root.appendingPathComponent("photo.jpg"),
        ])

        #expect(plan.files.map(\.relativeFolder) == [nil, nil])
        #expect(plan.files.map(\.source.lastPathComponent) == ["photo.jpg", "rapport.pdf"])
        #expect(plan.folders.isEmpty)
        #expect(plan.unreadableItems == 0)
    }

    @Test func folderTreeIsRecreatedWithEmptyFolders() async throws {
        let root = try makeTemporaryTree(
            files: ["Vacances/liste.txt", "Vacances/2024/plage.jpg"],
            folders: ["Vacances/2025"]
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = await FinderUploadPlan.make(from: [
            root.appendingPathComponent("Vacances", isDirectory: true),
        ])

        #expect(plan.folders == ["Vacances", "Vacances/2024", "Vacances/2025"])
        #expect(plan.files.map(\.relativeFolder) == ["Vacances", "Vacances/2024"])
        #expect(plan.files.map(\.source.lastPathComponent) == ["liste.txt", "plage.jpg"])
    }

    @Test func mixedSelectionKeepsTopLevelFilesAtDestination() async throws {
        let root = try makeTemporaryTree(files: ["rapport.pdf", "Photos/a.jpg"])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = await FinderUploadPlan.make(from: [
            root.appendingPathComponent("rapport.pdf"),
            root.appendingPathComponent("Photos", isDirectory: true),
        ])

        #expect(plan.folders == ["Photos"])
        #expect(plan.files.map(\.relativeFolder) == [nil, "Photos"])
    }

    @Test func dsStoreFilesAreSkipped() async throws {
        let root = try makeTemporaryTree(files: ["Photos/a.jpg", "Photos/.DS_Store"])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = await FinderUploadPlan.make(from: [
            root.appendingPathComponent("Photos", isDirectory: true),
        ])

        #expect(plan.files.map(\.source.lastPathComponent) == ["a.jpg"])
    }

    @Test func missingItemsAreCountedAsUnreadable() async throws {
        let plan = await FinderUploadPlan.make(from: [
            URL(fileURLWithPath: "/nonexistent/FinderUploadPlanTests/fichier.txt"),
        ])

        #expect(plan.files.isEmpty)
        #expect(plan.unreadableItems == 1)
    }

    @Test func folderCreationsSplitParentAndName() {
        var plan = FinderUploadPlan()
        plan.folders = ["Vacances", "Vacances/2024"]

        let creations = plan.folderCreations(under: "/partage")

        #expect(creations == [
            FileStationFolderCreation(parentPath: "/partage", name: "Vacances"),
            FileStationFolderCreation(parentPath: "/partage/Vacances", name: "2024"),
        ])
    }

    @Test func destinationFolderAppendsRelativePath() {
        let direct = FinderUploadPlan.File(
            source: URL(fileURLWithPath: "/tmp/a.txt"),
            relativeFolder: nil
        )
        let nested = FinderUploadPlan.File(
            source: URL(fileURLWithPath: "/tmp/Vacances/2024/plage.jpg"),
            relativeFolder: "Vacances/2024"
        )

        #expect(direct.destinationFolder(under: "/partage") == "/partage")
        #expect(nested.destinationFolder(under: "/partage") == "/partage/Vacances/2024")
    }
}
