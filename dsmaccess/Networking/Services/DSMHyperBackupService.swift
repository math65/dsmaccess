//
//  DSMHyperBackupService.swift
//  dsmaccess
//
//  Hyper Backup monitoring through the contracts observed on the NAS and in the official
//  DSM client.
//

import Foundation

@MainActor
final class DSMHyperBackupService {
    /// `SYNO.Backup.Task` advertises versions 1 and 2, but `list`, `get` and `status` only
    /// answer on version 1 — version 2 replies "no such method".
    private static let taskAPI = DSMAPI("SYNO.Backup.Task", preferredVersion: 1)
    private static let targetAPI = DSMAPI("SYNO.Backup.Target", preferredVersion: 1)
    /// The mirror image of the above: `SYNO.Backup.Version` only lists on version 2.
    private static let versionAPI = DSMAPI("SYNO.Backup.Version", preferredVersion: 2, minimumVersion: 2)
    private static let logAPI = DSMAPI("SYNO.SDS.Backup.Client.Common.Log", preferredVersion: 1)
    private static let statisticAPI = DSMAPI("SYNO.SDS.Backup.Client.Common.Statistic", preferredVersion: 1)
    private static let exploreFolderAPI = DSMAPI("SYNO.SDS.Backup.Client.Explore.Folder", preferredVersion: 1)
    private static let exploreFileAPI = DSMAPI("SYNO.SDS.Backup.Client.Explore.File", preferredVersion: 1)

    /// How the restore browser names itself to the backup engine. `copy` answers error 4401
    /// without it, whatever else the request carries, while the list methods accept its
    /// absence. The DSM client sends it with every explorer request, `restore` included, but
    /// only when its window was opened with a backend configured, which is why the value
    /// appears nowhere in the package documentation.
    private static let exploreBackend = "HyperBackup-backend"

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func tasks() async throws -> [HyperBackupTask] {
        try await transport.read(
            api: Self.taskAPI,
            method: "list",
            as: HyperBackupTaskList.self
        ).tasks
    }

    func state(taskID: Int) async throws -> HyperBackupTaskState {
        try await transport.read(
            api: Self.taskAPI,
            method: "status",
            parameters: ["task_id": .integer(taskID)],
            as: HyperBackupTaskState.self
        )
    }

    func target(taskID: Int) async throws -> HyperBackupTarget {
        try await transport.read(
            api: Self.targetAPI,
            method: "get",
            parameters: ["task_id": .integer(taskID)],
            as: HyperBackupTarget.self
        )
    }

    func versions(taskID: Int) async throws -> [HyperBackupVersion] {
        try await transport.read(
            api: Self.versionAPI,
            method: "list",
            parameters: ["task_id": .integer(taskID)],
            as: HyperBackupVersionList.self
        ).versions
    }

    /// The first level of a version. `File.list` refuses to list the root with error 4400, so
    /// the top comes from `Folder.list`, which answers a bare array and only ever holds
    /// folders. It needs the version: without it the call fails with error 4401.
    func backupRoot(taskID: Int, versionID: String) async throws -> [HyperBackupEntry] {
        try await transport.read(
            api: Self.exploreFolderAPI,
            method: "list",
            parameters: [
                "task_id": .integer(taskID),
                "version_id": .string(versionID),
            ],
            as: [HyperBackupEntry].self
        )
    }

    /// The contents of one folder, files included. `node` is relative to the backup root and
    /// carries no leading slash — `/Test` is rejected where `Test` is accepted.
    func backupEntries(
        taskID: Int,
        versionID: String,
        node: String
    ) async throws -> [HyperBackupEntry] {
        try await transport.read(
            api: Self.exploreFileAPI,
            method: "list",
            parameters: [
                "task_id": .integer(taskID),
                "version_id": .string(versionID),
                "node": .string(node),
            ],
            as: HyperBackupEntryPage.self
        ).entries
    }

    /// Copies entries out of a backup into a location the user chose, leaving the originals
    /// untouched. This is the operation DSM offers first, and the only one that can restore
    /// somewhere new: `restore` ignores its own destination and always writes back over the
    /// original.
    ///
    /// `destinationPath` is the physical volume path (`/volume1/Documents`); the share path
    /// `/Documents` fails with error 4401. The copied entries land directly under it, without
    /// their original folders being recreated. A destination that already holds them answers
    /// error 4462 rather than skipping in silence.
    func copyFromBackup(
        taskID: Int,
        versionID: String,
        node: String,
        sourcePaths: [String],
        destinationPath: String,
        overwrite: Bool
    ) async throws {
        try await transport.perform(
            api: Self.exploreFileAPI,
            method: "copy",
            parameters: [
                "action": .string("copy"),
                "task_id": .integer(taskID),
                "version_id": .string(versionID),
                "node": .string(node),
                "source_path": try .json(sourcePaths),
                "dest_path": .string(destinationPath),
                "overwrite": .boolean(overwrite),
                "backend": .string(Self.exploreBackend),
            ]
        )
    }

    /// Puts entries back where the backup took them from, replacing what is there now. DSM
    /// offers no choice here: its own client forces `overwrite` to true and derives the
    /// destination from the selection, so the confirmation is the only thing standing between
    /// the user and the loss of the current contents.
    ///
    /// Unlike `copy`, the paths stay relative to the backup root — `Test/notes` rather than
    /// `/volume1/Test/notes`. `originPath` is the path of the first selected entry, which is
    /// what the DSM client sends; a multiple selection was not measured.
    func restoreInPlaceFromBackup(
        taskID: Int,
        versionID: String,
        node: String,
        sourcePaths: [String],
        originPath: String
    ) async throws {
        try await transport.perform(
            api: Self.exploreFileAPI,
            method: "restore",
            parameters: [
                "action": .string("restore"),
                "task_id": .integer(taskID),
                "version_id": .string(versionID),
                "node": .string(node),
                "source_path": try .json(sourcePaths),
                "dest_path": .string(originPath),
                "overwrite": .boolean(true),
                "backend": .string(Self.exploreBackend),
            ]
        )
    }

    /// Pulls one file out of a backup and onto the Mac. `source_path` is a single string here,
    /// not the array `copy` and `restore` take: DSM downloads one entry at a time and keeps
    /// the button disabled on a folder.
    ///
    /// Two oddities measured on the DSM client rather than documented anywhere. The file name
    /// is appended to the CGI path (`entry.cgi/notes.txt`), which is what names what comes
    /// back; and `download_id` is minted by the client, which is how DSM then follows the
    /// preparation through `Explore.Job.list`.
    func backupDownloadURL(
        taskID: Int,
        versionID: String,
        node: String,
        sourcePath: String,
        fileName: String
    ) async throws -> URL {
        let route = try await transport.makeURL(
            api: Self.exploreFileAPI,
            method: "download",
            parameters: [
                "task_id": .integer(taskID),
                "version_id": .string(versionID),
                "node": .string(node),
                "source_path": .string(sourcePath),
                "support_utf8_name": .boolean(true),
                "download_id": .string(UUID().uuidString),
                "backend": .string(Self.exploreBackend),
            ]
        )
        return Self.appending(fileName: fileName, to: route)
    }

    func downloadFromBackup(
        taskID: Int,
        versionID: String,
        node: String,
        sourcePath: String,
        fileName: String,
        to destination: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws {
        let url = try await backupDownloadURL(
            taskID: taskID,
            versionID: versionID,
            node: node,
            sourcePath: sourcePath,
            fileName: fileName
        )
        // The NAS prepares the file before the first byte moves — on a busy machine, or
        // when the backup lives on a remote target the server has to fetch from, the
        // silence exceeded the transport's 20-second idle default. This is an idle
        // ceiling, not a duration: any received byte resets it.
        let (temporaryURL, response) = try await transport.download(
            from: url,
            timeoutInterval: 300,
            progress: progress
        )
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        // A refusal comes back as JSON where the file bytes were expected.
        if let mimeType = response.mimeType, mimeType.contains("json") {
            let data = try await MultipartBodyFile.readData(at: temporaryURL)
            let decoded = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
            guard !decoded.success else { throw DSMError.invalidResponse }
            throw transport.error(from: decoded.error)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
    }

    private static func appending(fileName: String, to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path += "/\(fileName)"
        return components.url ?? url
    }

    func logs(taskID: Int, offset: Int, limit: Int) async throws -> HyperBackupLogPage {
        try await transport.read(
            api: Self.logAPI,
            method: "list",
            parameters: [
                "task_id": .integer(taskID),
                "offset": .integer(offset),
                "limit": .integer(limit),
            ],
            as: HyperBackupLogPage.self
        )
    }

    func statistics(taskID: Int) async throws -> HyperBackupStatistics {
        try await transport.read(
            api: Self.statisticAPI,
            method: "get",
            parameters: ["task_id": .integer(taskID)],
            as: HyperBackupStatistics.self
        )
    }

    func backUp(taskID: Int) async throws {
        try await transport.perform(
            api: Self.taskAPI,
            method: "backup",
            parameters: ["task_id": .integer(taskID)]
        )
    }

    /// Cancelling needs the task state alongside its identifier. Sending only `task_id`
    /// fails with error 4400 even while DSM reports the run as cancellable.
    func cancel(taskID: Int, state: String) async throws {
        try await transport.perform(
            api: Self.taskAPI,
            method: "cancel",
            parameters: [
                "task_id": .integer(taskID),
                "task_state": .string(state),
            ]
        )
    }
}
