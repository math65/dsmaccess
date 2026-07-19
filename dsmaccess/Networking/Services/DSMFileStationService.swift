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
    private static let virtualFolderAPI = DSMAPI(
        "SYNO.FileStation.VirtualFolder",
        preferredVersion: 2,
        minimumVersion: 2
    )
    private static let thumbnailAPI = DSMAPI("SYNO.FileStation.Thumb", preferredVersion: 2)
    private static let downloadAPI = DSMAPI("SYNO.FileStation.Download", preferredVersion: 2)
    private static let createFolderAPI = DSMAPI("SYNO.FileStation.CreateFolder", preferredVersion: 2)
    private static let renameAPI = DSMAPI("SYNO.FileStation.Rename", preferredVersion: 2)
    private static let deleteAPI = DSMAPI("SYNO.FileStation.Delete", preferredVersion: 2)
    private static let uploadAPI = DSMAPI("SYNO.FileStation.Upload", preferredVersion: 3)
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

    private static let fileAdditionalFields = [
        "real_path", "size", "owner", "time", "perm", "type", "mount_point_type",
    ]
    private static let shareAdditionalFields = [
        "real_path", "owner", "time", "perm", "mount_point_type", "volume_status",
    ]

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
        try await shares(options: FileStationListOptions()).elements
    }

    func shares(options: FileStationListOptions) async throws -> FileStationPage<FileStationItem> {
        var parameters = listParameters(options: options, includesItemFilters: false)
        parameters["onlywritable"] = .boolean(options.onlyWritable)
        parameters["additional"] = try DSMParameter.json(Self.shareAdditionalFields)
        let result = try await transport.read(
            api: Self.listAPI,
            method: "list_share",
            parameters: parameters,
            as: FileStationShares.self
        )
        return FileStationPage(total: result.total, offset: result.offset, elements: result.shares)
    }

    func items(in folderPath: String) async throws -> [FileStationItem] {
        try await items(in: folderPath, options: FileStationListOptions()).elements
    }

    func items(
        in folderPath: String,
        options: FileStationListOptions
    ) async throws -> FileStationPage<FileStationItem> {
        var parameters = listParameters(options: options, includesItemFilters: true)
        parameters["folder_path"] = .string(folderPath)
        parameters["additional"] = try DSMParameter.json(Self.fileAdditionalFields)
        let result = try await transport.read(
            api: Self.listAPI,
            method: "list",
            parameters: parameters,
            as: FileStationFiles.self
        )
        return FileStationPage(total: result.total, offset: result.offset, elements: result.files)
    }

    func itemInformation(paths: [String]) async throws -> [FileStationItem] {
        guard !paths.isEmpty else { return [] }
        return try await transport.read(
            api: Self.listAPI,
            method: "getinfo",
            parameters: [
                "path": try DSMParameter.json(paths),
                "additional": try DSMParameter.json(Self.fileAdditionalFields),
            ],
            as: FileStationFiles.self
        ).files
    }

    func virtualFolders(
        of type: FileStationVirtualFolderType,
        options: FileStationListOptions = FileStationListOptions()
    ) async throws -> FileStationPage<FileStationItem> {
        var parameters = listParameters(options: options, includesItemFilters: false)
        parameters["type"] = .string(type.rawValue)
        parameters["additional"] = try DSMParameter.json(Self.shareAdditionalFields)
        let result = try await transport.read(
            api: Self.virtualFolderAPI,
            method: "list",
            parameters: parameters,
            as: FileStationVirtualFolders.self
        )
        return FileStationPage(total: result.total, offset: result.offset, elements: result.folders)
    }

    func thumbnail(
        path: String,
        size: FileStationThumbnailSize = .small,
        rotation: FileStationThumbnailRotation = .none
    ) async throws -> Data {
        let url = try await transport.makeURL(
            api: Self.thumbnailAPI,
            method: "get",
            parameters: [
                "path": .string(path),
                "size": .string(size.rawValue),
                "rotate": .integer(rotation.rawValue),
            ]
        )
        let (data, response) = try await transport.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        if response.mimeType?.contains("json") == true {
            let response = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
            guard !response.success else { throw DSMError.invalidResponse }
            throw transport.error(from: response.error)
        }
        guard !data.isEmpty else { throw DSMError.invalidResponse }
        return data
    }

    func download(path: String, to destination: URL) async throws {
        try await download(paths: [path], to: destination)
    }

    func download(paths: [String], to destination: URL) async throws {
        guard !paths.isEmpty else { return }
        let url = try await transport.makeURL(
            api: Self.downloadAPI,
            method: "download",
            parameters: ["path": try DSMParameter.json(paths), "mode": .string("download")]
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
        _ = try await createFolders([
            FileStationFolderCreation(parentPath: folderPath, name: name),
        ])
    }

    func createFolders(
        _ folders: [FileStationFolderCreation],
        forceParentFolders: Bool = false
    ) async throws -> [FileStationItem] {
        guard !folders.isEmpty else { return [] }
        return try await transport.value(
            api: Self.createFolderAPI,
            method: "create",
            parameters: [
                "folder_path": try DSMParameter.json(folders.map(\.parentPath)),
                "name": try DSMParameter.json(folders.map(\.name)),
                "force_parent": .boolean(forceParentFolders),
                "additional": try DSMParameter.json(Self.fileAdditionalFields),
            ],
            as: FileStationCreatedFolders.self
        ).folders
    }

    func rename(path: String, to name: String) async throws {
        _ = try await rename([
            FileStationRenameChange(path: path, name: name),
        ])
    }

    func rename(
        _ changes: [FileStationRenameChange],
        searchTaskID: String? = nil
    ) async throws -> [FileStationItem] {
        guard !changes.isEmpty else { return [] }
        var parameters: [String: DSMParameter] = [
            "path": try DSMParameter.json(changes.map(\.path)),
            "name": try DSMParameter.json(changes.map(\.name)),
            "additional": try DSMParameter.json(Self.fileAdditionalFields),
        ]
        if let searchTaskID, !searchTaskID.isEmpty {
            parameters["search_taskid"] = .string(searchTaskID)
        }
        return try await transport.value(
            api: Self.renameAPI,
            method: "rename",
            parameters: parameters,
            as: FileStationFiles.self
        ).files
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

    func upload(
        fileURL: URL,
        to folderPath: String,
        options: FileStationUploadOptions = FileStationUploadOptions()
    ) async throws {
        let resolved = try await transport.resolvedAPI(Self.uploadAPI)
        let boundary = "Boundary-\(UUID().uuidString)"
        var parameters: [String: DSMParameter] = [
            "path": .string(folderPath),
            "create_parents": .boolean(options.createParentFolders),
        ]
        if options.conflictPolicy != .ask {
            if resolved.version >= 3 {
                parameters["overwrite"] = .string(
                    options.conflictPolicy == .overwrite ? "overwrite" : "skip"
                )
            } else {
                parameters["overwrite"] = .boolean(options.conflictPolicy == .overwrite)
            }
        }
        addMilliseconds(options.modificationDate, key: "mtime", to: &parameters)
        addMilliseconds(options.creationDate, key: "crtime", to: &parameters)
        addMilliseconds(options.accessDate, key: "atime", to: &parameters)
        let route = try await transport.multipartRoute(
            api: Self.uploadAPI,
            method: "upload",
            parameters: parameters
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
        let links = try await createShareLinks(
            FileStationShareLinkCreation(
                paths: [path],
                password: password,
                expirationDate: expirationDate
            )
        )
        guard let url = links.first?.url else {
            throw DSMError.invalidResponse
        }
        return url
    }

    func createShareLinks(_ creation: FileStationShareLinkCreation) async throws -> [SharingLink] {
        guard !creation.paths.isEmpty else { return [] }
        var parameters: [String: DSMParameter] = [
            "path": try DSMParameter.json(creation.paths),
        ]
        addNonempty(creation.password, key: "password", to: &parameters)
        addNonempty(creation.expirationDate, key: "date_expired", to: &parameters)
        addNonempty(creation.availableDate, key: "date_available", to: &parameters)
        let links = try await transport.value(
            api: Self.sharingAPI,
            method: "create",
            parameters: parameters,
            as: FileStationCreatedShareLinks.self
        ).links
        if let failed = links.first(where: { $0.errorCode != 0 }) {
            throw DSMError.itemOperationFailed(
                code: failed.errorCode,
                item: failed.path,
                itemCode: failed.errorCode
            )
        }
        return try links.map { link in
            guard let id = link.id, let url = link.url else {
                throw DSMError.invalidResponse
            }
            return SharingLink(
                id: id,
                url: url,
                path: link.path,
                qrCode: link.qrCode,
                creationError: link.errorCode
            )
        }
    }

    func shareLinkInformation(id: String) async throws -> SharingLink {
        try await transport.read(
            api: Self.sharingAPI,
            method: "getinfo",
            parameters: ["id": .string(id)],
            as: SharingLink.self
        )
    }

    func shareLinks() async throws -> [SharingLink] {
        try await shareLinks(options: FileStationSharingListOptions()).elements
    }

    func shareLinks(
        options: FileStationSharingListOptions
    ) async throws -> FileStationPage<SharingLink> {
        var parameters: [String: DSMParameter] = [
            "offset": .integer(options.offset),
            "limit": .integer(options.limit),
            "sort_direction": .string(options.sortDirection.rawValue),
            "force_clean": .boolean(options.forceRefresh),
        ]
        if let sortBy = options.sortBy {
            parameters["sort_by"] = .string(sortBy.rawValue)
        }
        let result = try await transport.read(
            api: Self.sharingAPI,
            method: "list",
            parameters: parameters,
            as: SharingLinks.self
        )
        return FileStationPage(
            total: result.total ?? result.links.count,
            offset: result.offset ?? options.offset,
            elements: result.links
        )
    }

    func deleteShareLink(id: String) async throws {
        try await deleteShareLinks(ids: [id])
    }

    func deleteShareLinks(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await transport.perform(
            api: Self.sharingAPI,
            method: "delete",
            parameters: ["id": try DSMParameter.json(ids)]
        )
    }

    func clearInvalidShareLinks() async throws {
        try await transport.perform(api: Self.sharingAPI, method: "clear_invalid")
    }

    func editShareLinks(ids: [String], changes: FileStationShareLinkChanges) async throws {
        guard !ids.isEmpty else { return }
        var parameters: [String: DSMParameter] = ["id": try DSMParameter.json(ids)]
        if let password = changes.password {
            parameters["password"] = .string(password)
        }
        if let expirationDate = changes.expirationDate {
            parameters["date_expired"] = .string(expirationDate)
        }
        if let availableDate = changes.availableDate {
            parameters["date_available"] = .string(availableDate)
        }
        try await transport.perform(
            api: Self.sharingAPI,
            method: "edit",
            parameters: parameters
        )
    }

    func search(in folderPath: String, matching pattern: String) async throws -> [FileStationItem] {
        try await search(
            criteria: FileStationSearchCriteria(folderPaths: [folderPath], pattern: pattern)
        )
    }

    func search(
        criteria: FileStationSearchCriteria,
        resultOptions: FileStationSearchResultOptions = FileStationSearchResultOptions(),
        progress: (FileStationSearchProgress) -> Void = { _ in }
    ) async throws -> [FileStationItem] {
        guard !criteria.folderPaths.isEmpty else { return [] }
        let taskID = try await startSearch(criteria: criteria)
        do {
            for _ in 0..<operationPollLimit {
                try Task.checkCancellation()
                let result = try await searchResults(taskID: taskID, options: resultOptions)
                progress(
                    FileStationSearchProgress(
                        taskID: taskID,
                        isFinished: result.finished,
                        total: result.total,
                        files: result.files
                    )
                )
                if result.finished {
                    try await cleanSearch(taskIDs: [taskID])
                    return result.files
                }
                try await Task.sleep(for: operationPollInterval)
            }
            throw DSMError.network(String(localized: "Délai dépassé."))
        } catch {
            await discardSearchTask(taskID: taskID)
            throw error
        }
    }

    func startSearch(criteria: FileStationSearchCriteria) async throws -> String {
        guard !criteria.folderPaths.isEmpty else { throw DSMError.invalidResponse }
        var parameters: [String: DSMParameter] = [
            "folder_path": try DSMParameter.json(criteria.folderPaths),
            "recursive": .boolean(criteria.recursive),
            "filetype": .string(criteria.itemType.rawValue),
        ]
        addNonempty(criteria.pattern, key: "pattern", to: &parameters)
        addNonempty(criteria.extensions, key: "extension", to: &parameters)
        addInteger(criteria.minimumSize, key: "size_from", to: &parameters)
        addInteger(criteria.maximumSize, key: "size_to", to: &parameters)
        addSeconds(criteria.modifiedAfter, key: "mtime_from", to: &parameters)
        addSeconds(criteria.modifiedBefore, key: "mtime_to", to: &parameters)
        addSeconds(criteria.createdAfter, key: "crtime_from", to: &parameters)
        addSeconds(criteria.createdBefore, key: "crtime_to", to: &parameters)
        addSeconds(criteria.accessedAfter, key: "atime_from", to: &parameters)
        addSeconds(criteria.accessedBefore, key: "atime_to", to: &parameters)
        addNonempty(criteria.owner, key: "owner", to: &parameters)
        addNonempty(criteria.group, key: "group", to: &parameters)
        let task = try await transport.value(
            api: Self.searchAPI,
            method: "start",
            parameters: parameters,
            as: FileStationSearchTask.self
        )
        return task.taskid
    }

    func searchResults(
        taskID: String,
        options: FileStationSearchResultOptions = FileStationSearchResultOptions()
    ) async throws -> FileStationSearchResults {
        var parameters: [String: DSMParameter] = [
            "taskid": .string(taskID),
            "offset": .integer(options.offset),
            "limit": .integer(options.limit),
            "sort_by": .string(options.sortBy.rawValue),
            "sort_direction": .string(options.sortDirection.rawValue),
            "filetype": .string(options.itemType.rawValue),
            "additional": try DSMParameter.json(Self.fileAdditionalFields),
        ]
        addNonempty(options.pattern, key: "pattern", to: &parameters)
        return try await transport.read(
            api: Self.searchAPI,
            method: "list",
            parameters: parameters,
            as: FileStationSearchResults.self
        )
    }

    func stopSearch(taskIDs: [String]) async throws {
        guard !taskIDs.isEmpty else { return }
        try await transport.perform(
            api: Self.searchAPI,
            method: "stop",
            parameters: ["taskid": try DSMParameter.json(taskIDs)]
        )
    }

    func cleanSearch(taskIDs: [String]) async throws {
        guard !taskIDs.isEmpty else { return }
        try await transport.perform(
            api: Self.searchAPI,
            method: "clean",
            parameters: ["taskid": try DSMParameter.json(taskIDs)]
        )
    }

    func favorites() async throws -> [FileStationFavorite] {
        try await favorites(status: .all).elements
    }

    func favorites(
        status: FileStationFavoriteStatus,
        offset: Int = 0,
        limit: Int = 0
    ) async throws -> FileStationPage<FileStationFavorite> {
        let result = try await transport.read(
            api: Self.favoriteAPI,
            method: "list",
            parameters: [
                "offset": .integer(offset),
                "limit": .integer(limit),
                "status_filter": .string(status.rawValue),
                "additional": try DSMParameter.json(Self.fileAdditionalFields),
            ],
            as: FileStationFavorites.self
        )
        return FileStationPage(total: result.total, offset: result.offset, elements: result.favorites)
    }

    func addFavorite(path: String, name: String, index: Int = -1) async throws {
        try await transport.perform(
            api: Self.favoriteAPI,
            method: "add",
            parameters: ["path": .string(path), "name": .string(name), "index": .integer(index)]
        )
    }

    func removeFavorite(path: String) async throws {
        try await transport.perform(
            api: Self.favoriteAPI,
            method: "delete",
            parameters: ["path": .string(path)]
        )
    }

    func editFavorite(path: String, name: String) async throws {
        try await transport.perform(
            api: Self.favoriteAPI,
            method: "edit",
            parameters: ["path": .string(path), "name": .string(name)]
        )
    }

    func replaceFavorites(_ favorites: [FileStationFavorite]) async throws {
        try await transport.perform(
            api: Self.favoriteAPI,
            method: "replace_all",
            parameters: [
                "path": try DSMParameter.json(favorites.map(\.path)),
                "name": try DSMParameter.json(favorites.map(\.name)),
            ]
        )
    }

    func clearBrokenFavorites() async throws {
        try await transport.perform(api: Self.favoriteAPI, method: "clear_broken")
    }

    func compress(
        paths: [String],
        to destinationPath: String,
        options: FileStationCompressionOptions = FileStationCompressionOptions(),
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws {
        guard !paths.isEmpty else { return }
        var parameters: [String: DSMParameter] = [
            "path": try DSMParameter.json(paths),
            "dest_file_path": .string(destinationPath),
            "level": .string(options.level.rawValue),
            "mode": .string(options.mode.rawValue),
            "format": .string(options.format.rawValue),
        ]
        addNonempty(options.password, key: "password", to: &parameters)
        let task = try await transport.value(
            api: Self.compressAPI,
            method: "start",
            parameters: parameters,
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
        options: FileStationExtractionOptions = FileStationExtractionOptions(),
        progress: (FileOperationProgress) -> Void = { _ in }
    ) async throws {
        var parameters: [String: DSMParameter] = [
            "file_path": .string(archivePath),
            "dest_folder_path": .string(destinationFolder),
            "keep_dir": .boolean(options.keepsDirectoryStructure),
            "create_subfolder": .boolean(options.createsSubfolder),
        ]
        if let overwrite = overwriteParameter(for: options.conflictPolicy) {
            parameters["overwrite"] = overwrite
        }
        if let codepage = options.codepage {
            parameters["codepage"] = .string(codepage.rawValue)
        }
        addNonempty(options.password, key: "password", to: &parameters)
        if !options.itemIDs.isEmpty {
            parameters["item_id"] = try DSMParameter.json(options.itemIDs)
        }
        let task = try await transport.value(
            api: Self.extractAPI,
            method: "start",
            parameters: parameters,
            as: FileOperationTask.self
        )
        _ = try await waitForOperation(
            api: Self.extractAPI,
            kind: .extract,
            taskID: task.taskid,
            progress: progress
        )
    }

    func archiveItems(
        archivePath: String,
        options: FileStationArchiveListOptions = FileStationArchiveListOptions()
    ) async throws -> FileStationPage<FileStationArchiveItem> {
        var parameters: [String: DSMParameter] = [
            "file_path": .string(archivePath),
            "offset": .integer(options.offset),
            "limit": .integer(options.limit),
            "sort_by": .string(options.sortBy.rawValue),
            "sort_direction": .string(options.sortDirection.rawValue),
        ]
        if let codepage = options.codepage {
            parameters["codepage"] = .string(codepage.rawValue)
        }
        addNonempty(options.password, key: "password", to: &parameters)
        if let parentItemID = options.parentItemID {
            parameters["item_id"] = .integer(parentItemID)
        }
        let result = try await transport.read(
            api: Self.extractAPI,
            method: "list",
            parameters: parameters,
            as: FileStationArchiveItems.self
        )
        return FileStationPage(total: result.total, offset: options.offset, elements: result.items)
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
        try await backgroundTasks(options: FileStationBackgroundTaskListOptions()).elements
    }

    func backgroundTasks(
        options: FileStationBackgroundTaskListOptions
    ) async throws -> FileStationPage<FileStationBackgroundTask> {
        var parameters: [String: DSMParameter] = [
            "offset": .integer(options.offset),
            "limit": .integer(options.limit),
            "sort_by": .string(options.sortBy.rawValue),
            "sort_direction": .string(options.sortDirection.rawValue),
        ]
        let filterableKinds = options.apiKinds.filter {
            switch $0 {
            case .copyMove, .delete, .extract, .compress: true
            case .directorySize, .checksum: false
            }
        }
        if !filterableKinds.isEmpty {
            parameters["api_filter"] = try DSMParameter.json(filterableKinds.map(\.rawValue))
        }
        let result = try await transport.read(
            api: Self.backgroundTaskAPI,
            method: "list",
            parameters: parameters,
            as: FileStationBackgroundTasks.self
        )
        return FileStationPage(total: result.total, offset: result.offset, elements: result.tasks)
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

    private func discardSearchTask(taskID: String) async {
        do {
            try await stopSearch(taskIDs: [taskID])
        } catch {
            // L'erreur qui a interrompu la recherche reste le résultat principal.
        }
        do {
            try await cleanSearch(taskIDs: [taskID])
        } catch {
            // La base temporaire peut encore être supprimée par DSM à l'expiration de la tâche.
        }
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

    private func listParameters(
        options: FileStationListOptions,
        includesItemFilters: Bool
    ) -> [String: DSMParameter] {
        var parameters: [String: DSMParameter] = [
            "offset": .integer(options.offset),
            "limit": .integer(options.limit),
            "sort_by": .string(options.sortBy.rawValue),
            "sort_direction": .string(options.sortDirection.rawValue),
        ]
        if includesItemFilters {
            parameters["filetype"] = .string(options.itemType.rawValue)
            addNonempty(options.pattern, key: "pattern", to: &parameters)
            addNonempty(options.goToPath, key: "goto_path", to: &parameters)
        }
        return parameters
    }

    private func addNonempty(
        _ value: String?,
        key: String,
        to parameters: inout [String: DSMParameter]
    ) {
        if let value, !value.isEmpty {
            parameters[key] = .string(value)
        }
    }

    private func addInteger(
        _ value: Int64?,
        key: String,
        to parameters: inout [String: DSMParameter]
    ) {
        if let value, let integer = Int(exactly: value) {
            parameters[key] = .integer(integer)
        }
    }

    private func addSeconds(
        _ date: Date?,
        key: String,
        to parameters: inout [String: DSMParameter]
    ) {
        if let date {
            parameters[key] = .integer(Int(date.timeIntervalSince1970))
        }
    }

    private func addMilliseconds(
        _ date: Date?,
        key: String,
        to parameters: inout [String: DSMParameter]
    ) {
        if let date {
            parameters[key] = .integer(Int(date.timeIntervalSince1970 * 1_000))
        }
    }

}
