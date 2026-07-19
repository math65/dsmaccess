//
//  DSMFileStationService.swift
//  dsmaccess
//
//  Navigation et opérations de base sur les fichiers du NAS.
//

import Foundation

@MainActor
final class DSMFileStationService {
    private static let infoAPI = DSMAPI("SYNO.FileStation.Info", preferredVersion: 2, minimumVersion: 2)
    private static let listAPI = DSMAPI("SYNO.FileStation.List", preferredVersion: 2)
    private static let downloadAPI = DSMAPI("SYNO.FileStation.Download", preferredVersion: 2)
    private static let createFolderAPI = DSMAPI("SYNO.FileStation.CreateFolder", preferredVersion: 2)
    private static let renameAPI = DSMAPI("SYNO.FileStation.Rename", preferredVersion: 2)
    private static let deleteAPI = DSMAPI("SYNO.FileStation.Delete", preferredVersion: 2)
    private static let uploadAPI = DSMAPI("SYNO.FileStation.Upload", preferredVersion: 2)
    private static let copyMoveAPI = DSMAPI("SYNO.FileStation.CopyMove", preferredVersion: 3)
    private static let sharingAPI = DSMAPI("SYNO.FileStation.Sharing", preferredVersion: 3)
    private static let searchAPI = DSMAPI("SYNO.FileStation.Search", preferredVersion: 2, minimumVersion: 2)
    private static let favoriteAPI = DSMAPI("SYNO.FileStation.Favorite", preferredVersion: 2, minimumVersion: 2)
    private static let compressAPI = DSMAPI("SYNO.FileStation.Compress", preferredVersion: 3, minimumVersion: 3)
    private static let extractAPI = DSMAPI("SYNO.FileStation.Extract", preferredVersion: 2, minimumVersion: 2)
    private static let directorySizeAPI = DSMAPI("SYNO.FileStation.DirSize", preferredVersion: 2, minimumVersion: 2)
    private static let checksumAPI = DSMAPI("SYNO.FileStation.MD5", preferredVersion: 2, minimumVersion: 2)
    private static let permissionAPI = DSMAPI(
        "SYNO.FileStation.CheckPermission",
        preferredVersion: 3,
        minimumVersion: 3
    )
    private static let backgroundTaskAPI = DSMAPI(
        "SYNO.FileStation.BackgroundTask",
        preferredVersion: 3,
        minimumVersion: 3
    )

    private let transport: DSMTransport
    private let operationPollInterval: Duration
    private let operationPollLimit: Int

    init(
        transport: DSMTransport,
        operationPollInterval: Duration = .milliseconds(500),
        operationPollLimit: Int = 600
    ) {
        self.transport = transport
        self.operationPollInterval = operationPollInterval
        self.operationPollLimit = operationPollLimit
    }

    func capabilities() async throws -> FileStationCapabilities {
        let supportedFeatures = Set(
            FileStationFeature.allCases.filter {
                transport.capabilities.supports($0.requiredAPI)
            }
        )
        let information: FileStationInfo? = if supportedFeatures.contains(.information) {
            try await information()
        } else {
            nil
        }
        return FileStationCapabilities(
            supportedFeatures: supportedFeatures,
            information: information
        )
    }

    func information() async throws -> FileStationInfo {
        try await transport.read(api: Self.infoAPI, method: "get", as: FileStationInfo.self)
    }

    func shares() async throws -> [FileStationItem] {
        let result = try await transport.read(
            api: Self.listAPI,
            method: "list_share",
            parameters: [
                "additional": try DSMParameter.json(["owner", "time", "perm", "volume_status"]),
            ],
            as: FileStationShares.self
        )
        return result.shares
    }

    func items(in folderPath: String) async throws -> [FileStationItem] {
        let result = try await transport.read(
            api: Self.listAPI,
            method: "list",
            parameters: [
                "folder_path": .string(folderPath),
                "additional": try DSMParameter.json(["real_path", "size", "owner", "time", "perm", "type"]),
            ],
            as: FileStationFiles.self
        )
        return result.files
    }

    func download(path: String, to destination: URL) async throws {
        let url = try await transport.makeURL(
            api: Self.downloadAPI,
            method: "download",
            parameters: ["path": .string(path), "mode": .string("download")]
        )
        let (temporaryURL, response) = try await transport.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        if let mimeType = response.mimeType, mimeType.contains("json") {
            let data = try await MultipartBodyFile.readData(at: temporaryURL)
            let response = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
            guard !response.success else { throw DSMError.invalidResponse }
            throw transport.error(from: response.error)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
    }

    func createFolder(in folderPath: String, name: String) async throws {
        try await transport.perform(
            api: Self.createFolderAPI,
            method: "create",
            parameters: ["folder_path": .string(folderPath), "name": .string(name)]
        )
    }

    func rename(path: String, to name: String) async throws {
        try await transport.perform(
            api: Self.renameAPI,
            method: "rename",
            parameters: ["path": .string(path), "name": .string(name)]
        )
    }

    func delete(path: String) async throws {
        try await delete(paths: [path])
    }

    func delete(
        paths: [String],
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws {
        guard !paths.isEmpty else { return }
        let resolved = try await transport.resolvedAPI(Self.deleteAPI)
        if resolved.version < 2 {
            for path in paths {
                try await transport.perform(
                    api: Self.deleteAPI,
                    method: "delete",
                    parameters: ["path": .string(path), "recursive": .boolean(true)]
                )
            }
            return
        }

        let task = try await transport.value(
            api: Self.deleteAPI,
            method: "start",
            parameters: [
                "path": try DSMParameter.json(paths),
                "recursive": .boolean(true),
            ],
            as: FileOperationTask.self
        )
        _ = try await waitForOperation(
            api: Self.deleteAPI,
            kind: .delete,
            taskID: task.taskid,
            progress: progress
        )
    }

    func upload(fileURL: URL, to folderPath: String) async throws {
        let boundary = "Boundary-\(UUID().uuidString)"
        let route = try await transport.multipartRoute(
            api: Self.uploadAPI,
            method: "upload",
            parameters: [
                "path": .string(folderPath),
                "create_parents": .boolean(true),
                "overwrite": .boolean(false),
            ]
        )
        let bodyURL = try await MultipartBodyFile.create(
            fields: route.fields,
            fileURL: fileURL,
            fileFieldName: "file",
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: route.url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await transport.upload(for: request, fromFile: bodyURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        let result = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
        guard result.success else {
            throw transport.error(from: result.error)
        }
    }

    func copyMove(
        path: String,
        to destinationFolder: String,
        removeSource: Bool,
        conflictPolicy: FileConflictPolicy = .ask,
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws {
        try await copyMove(
            paths: [path],
            to: destinationFolder,
            removeSource: removeSource,
            conflictPolicy: conflictPolicy,
            progress: progress
        )
    }

    func copyMove(
        paths: [String],
        to destinationFolder: String,
        removeSource: Bool,
        conflictPolicy: FileConflictPolicy = .ask,
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws {
        guard !paths.isEmpty else { return }
        var parameters: [String: DSMParameter] = [
            "path": try DSMParameter.json(paths),
            "dest_folder_path": .string(destinationFolder),
            "remove_src": .boolean(removeSource),
            "accurate_progress": .boolean(true),
        ]
        if let overwrite = overwriteParameter(for: conflictPolicy) {
            parameters["overwrite"] = overwrite
        }
        let task = try await transport.value(
            api: Self.copyMoveAPI,
            method: "start",
            parameters: parameters,
            as: CopyMoveTask.self
        )

        _ = try await waitForOperation(
            api: Self.copyMoveAPI,
            kind: .copyMove,
            taskID: task.taskid,
            progress: progress
        )
    }

    func createShareLink(path: String, password: String?, expirationDate: String?) async throws -> String {
        var parameters: [String: DSMParameter] = ["path": try DSMParameter.json([path])]
        if let password, !password.isEmpty { parameters["password"] = .string(password) }
        if let expirationDate, !expirationDate.isEmpty { parameters["date_expired"] = .string(expirationDate) }
        let result = try await transport.value(
            api: Self.sharingAPI,
            method: "create",
            parameters: parameters,
            as: SharingLinks.self
        )
        guard let url = result.links.first?.url else {
            throw DSMError.invalidResponse
        }
        return url
    }

    func shareLinks() async throws -> [SharingLink] {
        try await transport.read(
            api: Self.sharingAPI,
            method: "list",
            as: SharingLinks.self
        ).links
    }

    func deleteShareLink(id: String) async throws {
        try await transport.perform(
            api: Self.sharingAPI,
            method: "delete",
            parameters: ["id": .string(id)]
        )
    }

    func search(in folderPath: String, matching pattern: String) async throws -> [FileStationItem] {
        let task = try await transport.value(
            api: Self.searchAPI,
            method: "start",
            parameters: [
                "folder_path": try DSMParameter.json([folderPath]),
                "recursive": .boolean(true),
                "pattern": .string(pattern),
                "filetype": "all",
            ],
            as: FileStationSearchTask.self
        )

        do {
            for _ in 0..<120 {
                try Task.checkCancellation()
                let result = try await transport.read(
                    api: Self.searchAPI,
                    method: "list",
                    parameters: [
                        "taskid": .string(task.taskid),
                        "limit": .integer(-1),
                        "additional": try DSMParameter.json(["real_path", "size", "owner", "time", "perm", "type"]),
                    ],
                    as: FileStationSearchResults.self
                )
                if result.finished {
                    try? await cleanSearch(taskID: task.taskid)
                    return result.files
                }
                try await Task.sleep(for: .milliseconds(500))
            }
            try? await cleanSearch(taskID: task.taskid)
            throw DSMError.network(String(localized: "Délai dépassé."))
        } catch {
            try? await transport.perform(
                api: Self.searchAPI,
                method: "stop",
                parameters: ["taskid": .string(task.taskid)]
            )
            try? await cleanSearch(taskID: task.taskid)
            throw error
        }
    }

    func favorites() async throws -> [FileStationFavorite] {
        try await transport.read(
            api: Self.favoriteAPI,
            method: "list",
            parameters: ["limit": .integer(0), "status_filter": "all"],
            as: FileStationFavorites.self
        ).favorites
    }

    func addFavorite(path: String, name: String) async throws {
        try await transport.perform(
            api: Self.favoriteAPI,
            method: "add",
            parameters: ["path": .string(path), "name": .string(name), "index": .integer(-1)]
        )
    }

    func removeFavorite(path: String) async throws {
        try await transport.perform(
            api: Self.favoriteAPI,
            method: "delete",
            parameters: ["path": .string(path)]
        )
    }

    func compress(
        paths: [String],
        to destinationPath: String,
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws {
        guard !paths.isEmpty else { return }
        let task = try await transport.value(
            api: Self.compressAPI,
            method: "start",
            parameters: [
                "path": try DSMParameter.json(paths),
                "dest_file_path": .string(destinationPath),
                "level": "moderate",
                "mode": "add",
                "format": "zip",
            ],
            as: FileOperationTask.self
        )
        _ = try await waitForOperation(
            api: Self.compressAPI,
            kind: .compress,
            taskID: task.taskid,
            progress: progress
        )
    }

    func extract(
        archivePath: String,
        to destinationFolder: String,
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws {
        let task = try await transport.value(
            api: Self.extractAPI,
            method: "start",
            parameters: [
                "file_path": .string(archivePath),
                "dest_folder_path": .string(destinationFolder),
                "overwrite": .boolean(false),
                "keep_dir": .boolean(true),
                "create_subfolder": .boolean(true),
            ],
            as: FileOperationTask.self
        )
        _ = try await waitForOperation(
            api: Self.extractAPI,
            kind: .extract,
            taskID: task.taskid,
            progress: progress
        )
    }

    func checkWritePermission(
        in folderPath: String,
        filename: String,
        conflictPolicy: FileConflictPolicy = .ask,
        createOnly: Bool = true
    ) async throws {
        var parameters: [String: DSMParameter] = [
            "path": .string(folderPath),
            "filename": .string(filename),
            "create_only": .boolean(createOnly),
        ]
        if let overwrite = overwriteParameter(for: conflictPolicy) {
            parameters["overwrite"] = overwrite
        }
        try await transport.perform(
            api: Self.permissionAPI,
            method: "write",
            parameters: parameters
        )
    }

    func directorySize(
        paths: [String],
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws -> FileStationDirectorySize {
        guard !paths.isEmpty else {
            return FileStationDirectorySize(directoryCount: 0, fileCount: 0, totalSize: 0)
        }
        let task = try await transport.value(
            api: Self.directorySizeAPI,
            method: "start",
            parameters: ["path": try DSMParameter.json(paths)],
            as: FileOperationTask.self
        )

        do {
            for _ in 0..<operationPollLimit {
                try Task.checkCancellation()
                let status = try await transport.read(
                    api: Self.directorySizeAPI,
                    method: "status",
                    parameters: ["taskid": .string(task.taskid)],
                    as: FileStationDirectorySizeStatus.self
                )
                progress(
                    FileOperationProgress(
                        kind: .directorySize,
                        taskID: task.taskid,
                        isFinished: status.finished,
                        fractionCompleted: nil,
                        processedSize: status.totalSize,
                        totalSize: nil,
                        processedItemCount: status.fileCount,
                        totalItemCount: nil,
                        currentPath: paths.first,
                        destinationPath: nil
                    )
                )
                if status.finished {
                    guard let directoryCount = status.directoryCount,
                          let fileCount = status.fileCount,
                          let totalSize = status.totalSize else {
                        throw DSMError.invalidResponse
                    }
                    return FileStationDirectorySize(
                        directoryCount: directoryCount,
                        fileCount: fileCount,
                        totalSize: totalSize
                    )
                }
                try await Task.sleep(for: operationPollInterval)
            }
            throw DSMError.network(String(localized: "Délai dépassé."))
        } catch {
            if DSMError.isCancellation(error) {
                await stopAfterCancellation(api: Self.directorySizeAPI, taskID: task.taskid)
            }
            throw error
        }
    }

    func checksum(
        path: String,
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws -> String {
        let task = try await transport.value(
            api: Self.checksumAPI,
            method: "start",
            parameters: ["file_path": .string(path)],
            as: FileOperationTask.self
        )

        do {
            for _ in 0..<operationPollLimit {
                try Task.checkCancellation()
                let status = try await transport.read(
                    api: Self.checksumAPI,
                    method: "status",
                    parameters: ["taskid": .string(task.taskid)],
                    as: FileStationChecksumStatus.self
                )
                progress(
                    FileOperationProgress(
                        kind: .checksum,
                        taskID: task.taskid,
                        isFinished: status.finished,
                        fractionCompleted: status.finished ? 1 : nil,
                        processedSize: nil,
                        totalSize: nil,
                        processedItemCount: nil,
                        totalItemCount: nil,
                        currentPath: path,
                        destinationPath: nil
                    )
                )
                if status.finished {
                    guard let checksum = status.checksum, !checksum.isEmpty else {
                        throw DSMError.invalidResponse
                    }
                    return checksum
                }
                try await Task.sleep(for: operationPollInterval)
            }
            throw DSMError.network(String(localized: "Délai dépassé."))
        } catch {
            if DSMError.isCancellation(error) {
                await stopAfterCancellation(api: Self.checksumAPI, taskID: task.taskid)
            }
            throw error
        }
    }

    func backgroundTasks() async throws -> [FileStationBackgroundTask] {
        try await transport.read(
            api: Self.backgroundTaskAPI,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(0),
                "sort_by": .string("crtime"),
                "sort_direction": .string("desc"),
            ],
            as: FileStationBackgroundTasks.self
        ).tasks
    }

    func clearFinishedBackgroundTasks(taskIDs: [String] = []) async throws {
        var parameters: [String: DSMParameter] = [:]
        if !taskIDs.isEmpty {
            parameters["taskid"] = try DSMParameter.json(taskIDs)
        }
        try await transport.perform(
            api: Self.backgroundTaskAPI,
            method: "clear_finished",
            parameters: parameters
        )
    }

    func stopOperation(kind: FileOperationKind, taskID: String) async throws {
        try await transport.perform(
            api: api(for: kind),
            method: "stop",
            parameters: ["taskid": .string(taskID)]
        )
    }

    private func cleanSearch(taskID: String) async throws {
        try await transport.perform(
            api: Self.searchAPI,
            method: "clean",
            parameters: ["taskid": .string(taskID)]
        )
    }

    private func waitForOperation(
        api: DSMAPI,
        kind: FileOperationKind,
        taskID: String,
        progress: (FileOperationProgress) -> Void
    ) async throws -> FileOperationProgress {
        do {
            for _ in 0..<operationPollLimit {
                try Task.checkCancellation()
                let status = try await transport.read(
                    api: api,
                    method: "status",
                    parameters: ["taskid": .string(taskID)],
                    as: FileOperationStatus.self
                )
                let update = operationProgress(kind: kind, taskID: taskID, status: status)
                progress(update)
                if status.finished { return update }
                try await Task.sleep(for: operationPollInterval)
            }
            throw DSMError.network(String(localized: "Délai dépassé."))
        } catch {
            if DSMError.isCancellation(error) {
                await stopAfterCancellation(api: api, taskID: taskID)
            }
            throw error
        }
    }

    private func operationProgress(
        kind: FileOperationKind,
        taskID: String,
        status: FileOperationStatus
    ) -> FileOperationProgress {
        let total = status.total.flatMap { $0 >= 0 ? $0 : nil }
        let derivedProgress: Double? = if let explicit = status.progress {
            explicit
        } else if let processedSize = status.processedSize, let total, total > 0 {
            Double(processedSize) / Double(total)
        } else if let processedCount = status.processedCount, let total, total > 0 {
            Double(processedCount) / Double(total)
        } else if status.finished {
            1
        } else {
            nil
        }
        return FileOperationProgress(
            kind: kind,
            taskID: taskID,
            isFinished: status.finished,
            fractionCompleted: derivedProgress,
            processedSize: status.processedSize,
            totalSize: status.processedSize == nil ? nil : total,
            processedItemCount: status.processedCount,
            totalItemCount: status.processedCount == nil ? nil : total.flatMap(Int.init(exactly:)),
            currentPath: status.processingPath ?? status.path,
            destinationPath: status.destinationFolderPath ?? status.destinationFilePath
        )
    }

    private func stopAfterCancellation(api: DSMAPI, taskID: String) async {
        do {
            try await transport.perform(
                api: api,
                method: "stop",
                parameters: ["taskid": .string(taskID)]
            )
        } catch {
            // L'annulation demandée par l'utilisateur reste le résultat principal. La tâche
            // demeure visible dans BackgroundTask si DSM n'a pas pu traiter l'arrêt.
        }
    }

    private func api(for kind: FileOperationKind) -> DSMAPI {
        switch kind {
        case .copyMove: Self.copyMoveAPI
        case .delete: Self.deleteAPI
        case .extract: Self.extractAPI
        case .compress: Self.compressAPI
        case .directorySize: Self.directorySizeAPI
        case .checksum: Self.checksumAPI
        }
    }

    private func overwriteParameter(for policy: FileConflictPolicy) -> DSMParameter? {
        switch policy {
        case .ask: nil
        case .skip: .boolean(false)
        case .overwrite: .boolean(true)
        }
    }

}
