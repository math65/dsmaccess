import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMFileStationServiceTests {
    @Test func reportsOnlyCompatibleFileStationFeatures() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"is_manager":true,"support_virtual_protocol":"cifs,iso","support_sharing":true,"hostname":"DiskStation"}}"#.utf8
            )),
        ])
        let service = makeService(
            stub: stub,
            entries: [
                "SYNO.FileStation.Info": entry(maxVersion: 2),
                "SYNO.FileStation.List": entry(maxVersion: 2),
                "SYNO.FileStation.CheckPermission": entry(maxVersion: 2),
                "SYNO.FileStation.BackgroundTask": entry(maxVersion: 3),
            ]
        )

        let capabilities = try await service.capabilities()

        #expect(capabilities.supports(.information))
        #expect(capabilities.supports(.browsing))
        #expect(capabilities.supports(.metadata))
        #expect(!capabilities.supports(.writePermission))
        #expect(capabilities.supports(.backgroundTasks))
        #expect(capabilities.information?.supportedVirtualProtocols == ["cifs", "iso"])
        #expect(capabilities.information?.supportsSharing == true)
    }

    @Test func copyMoveUsesConflictPolicyAndReportsProgress() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"taskid":"copy-1"}}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"finished":false,"processed_size":"25","total":"100","progress":"0.25","path":"/source/file","dest_folder_path":"/target"}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"finished":true,"processed_size":100,"total":100,"progress":1,"path":"/source/file","dest_folder_path":"/target"}}"#.utf8
            )),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.CopyMove": entry(maxVersion: 3)]
        )
        var updates: [FileOperationProgress] = []

        try await service.copyMove(
            paths: ["/source/file"],
            to: "/target",
            removeSource: false,
            conflictPolicy: .overwrite,
            progress: { updates.append($0) }
        )

        let requests = await stub.requests
        let start = try query(from: requests[0])
        #expect(start["method"] == "start")
        #expect(start["overwrite"] == "true")
        #expect(start["accurate_progress"] == "true")
        #expect(updates.map(\.normalizedFraction) == [0.25, 1])
        #expect(updates.last?.isFinished == true)
        #expect(updates.last?.processedSize == 100)
    }

    @Test func calculatesDirectorySizeWithoutInventingMissingValues() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"taskid":"size-1"}}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"finished":true,"num_dir":"3","num_file":"14","total_size":"8192"}}"#.utf8
            )),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.DirSize": entry(maxVersion: 2)]
        )

        let size = try await service.directorySize(paths: ["/documents"])

        #expect(size == FileStationDirectorySize(directoryCount: 3, fileCount: 14, totalSize: 8192))
    }

    @Test func listsAndClearsFinishedBackgroundTasks() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"total":1,"offset":0,"tasks":[{"api":"SYNO.FileStation.Delete","version":"2","method":"start","taskid":"delete-1","finished":"true","crtime":"1710000000","processed_num":"4","total":"4","progress":"1"}]}}"#.utf8
            )),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.BackgroundTask": entry(maxVersion: 3)]
        )

        let tasks = try await service.backgroundTasks()
        try await service.clearFinishedBackgroundTasks(taskIDs: ["delete-1"])

        let task = try #require(tasks.first)
        #expect(task.taskID == "delete-1")
        #expect(task.finished)
        #expect(task.processedCount == 4)
        let requests = await stub.requests
        let clear = try query(from: requests[1])
        #expect(clear["method"] == "clear_finished")
        let encodedIDs = try #require(clear["taskid"])
        #expect(try JSONDecoder().decode([String].self, from: Data(encodedIDs.utf8)) == ["delete-1"])
    }

    @Test func preservesPerItemErrorDetails() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":false,"error":{"code":1100,"errors":[{"code":418,"path":"/documents/:"}]}}"#.utf8
            )),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.CreateFolder": entry(maxVersion: 2)]
        )

        await #expect(
            throws: DSMError.itemOperationFailed(
                code: 1100,
                item: "/documents/:",
                itemCode: 418
            )
        ) {
            try await service.createFolder(in: "/documents", name: ":")
        }
    }

    @Test func listsFilesWithPublishedPaginationSortingAndMetadata() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"total":"9","offset":"2","files":[{"name":"image.jpg","path":"/photo/image.jpg","isdir":false,"additional":{"size":2048,"mount_point_type":"remote","owner":{"user":"admin","group":"users","uid":1024,"gid":100},"perm":{"posix":644,"is_acl_mode":true,"acl":{"read":true,"write":false,"del":false,"exec":false,"append":false}}}}]}}"#.utf8
            )),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.List": entry(maxVersion: 2)]
        )

        let page = try await service.items(
            in: "/photo",
            options: FileStationListOptions(
                offset: 2,
                limit: 3,
                sortBy: .size,
                sortDirection: .descending,
                pattern: "*.jpg",
                itemType: .file,
                goToPath: "/photo/image.jpg"
            )
        )

        #expect(page.total == 9)
        #expect(page.offset == 2)
        let item = try #require(page.elements.first)
        #expect(item.additional?.owner?.uid == 1024)
        #expect(item.additional?.permission?.acl?.read == true)
        #expect(item.additional?.mountPointType == "remote")
        let request = try query(from: try #require(await stub.requests.first))
        #expect(request["method"] == "list")
        #expect(request["offset"] == "2")
        #expect(request["limit"] == "3")
        #expect(request["sort_by"] == "size")
        #expect(request["sort_direction"] == "desc")
        #expect(request["pattern"] == "*.jpg")
        #expect(request["filetype"] == "file")
        #expect(request["goto_path"] == "/photo/image.jpg")
    }

    @Test func runsAdvancedSearchAndCleansItsTemporaryDatabase() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"taskid":"search-1"}}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"total":1,"offset":0,"finished":false,"files":[{"name":"report.pdf","path":"/documents/report.pdf","isdir":false}]}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"total":1,"offset":0,"finished":true,"files":[{"name":"report.pdf","path":"/documents/report.pdf","isdir":false}]}}"#.utf8
            )),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.Search": entry(maxVersion: 2)]
        )
        var updates: [FileStationSearchProgress] = []
        let after = Date(timeIntervalSince1970: 1_700_000_000)

        let files = try await service.search(
            criteria: FileStationSearchCriteria(
                folderPaths: ["/documents"],
                recursive: false,
                pattern: "report*",
                extensions: "pdf,docx",
                itemType: .file,
                minimumSize: 100,
                maximumSize: 10_000,
                modifiedAfter: after,
                owner: "admin",
                group: "users"
            ),
            resultOptions: FileStationSearchResultOptions(
                sortBy: .modifiedTime,
                sortDirection: .descending
            ),
            progress: { updates.append($0) }
        )

        #expect(files.map(\.path) == ["/documents/report.pdf"])
        #expect(updates.map(\.isFinished) == [false, true])
        let requests = await stub.requests
        let start = try query(from: requests[0])
        #expect(start["method"] == "start")
        #expect(start["recursive"] == "false")
        #expect(start["extension"] == "pdf,docx")
        #expect(start["size_from"] == "100")
        #expect(start["size_to"] == "10000")
        #expect(start["mtime_from"] == "1700000000")
        #expect(start["owner"] == "admin")
        let list = try query(from: requests[1])
        #expect(list["limit"] == "-1")
        #expect(list["sort_by"] == "mtime")
        #expect(list["sort_direction"] == "desc")
        let clean = try query(from: requests[3])
        #expect(clean["method"] == "clean")
        let encodedIDs = try #require(clean["taskid"])
        #expect(try JSONDecoder().decode([String].self, from: Data(encodedIDs.utf8)) == ["search-1"])
    }

    @Test func exposesVirtualFoldersAndCompleteFavoriteOperations() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"total":1,"offset":0,"folders":[{"name":"Remote","path":"/video/Remote","isdir":true,"additional":{"mount_point_type":"remote","volume_status":{"freespace":1000,"totalspace":2000,"readonly":false}}}]}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"total":1,"offset":0,"favorites":[{"name":"Videos","path":"/video","isdir":true,"status":"valid"}]}}"#.utf8
            )),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(
            stub: stub,
            entries: [
                "SYNO.FileStation.VirtualFolder": entry(maxVersion: 2),
                "SYNO.FileStation.Favorite": entry(maxVersion: 2),
            ]
        )

        let virtual = try await service.virtualFolders(of: .cifs)
        let favorites = try await service.favorites(status: .valid)
        try await service.editFavorite(path: "/video", name: "Mes vidéos")
        try await service.replaceFavorites(favorites.elements)
        try await service.clearBrokenFavorites()

        #expect(virtual.elements.first?.additional?.volumeStatus?.freeSpace == 1000)
        #expect(favorites.elements.first?.isAvailable == true)
        let requests = await stub.requests
        #expect(try query(from: requests[0])["type"] == "cifs")
        #expect(try query(from: requests[1])["status_filter"] == "valid")
        #expect(try query(from: requests[2])["method"] == "edit")
        #expect(try query(from: requests[3])["method"] == "replace_all")
        #expect(try query(from: requests[4])["method"] == "clear_broken")
    }

    @Test func createsAndRenamesMultipleFoldersInOneRequest() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"folders":[{"name":"One","path":"/documents/One","isdir":true},{"name":"Two","path":"/documents/Two","isdir":true}]}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"files":[{"name":"First","path":"/documents/First","isdir":true},{"name":"Second","path":"/documents/Second","isdir":true}]}}"#.utf8
            )),
        ])
        let service = makeService(
            stub: stub,
            entries: [
                "SYNO.FileStation.CreateFolder": entry(maxVersion: 2),
                "SYNO.FileStation.Rename": entry(maxVersion: 2),
            ]
        )

        let created = try await service.createFolders(
            [
                FileStationFolderCreation(parentPath: "/documents", name: "One"),
                FileStationFolderCreation(parentPath: "/documents", name: "Two"),
            ],
            forceParentFolders: true
        )
        let renamed = try await service.rename(
            [
                FileStationRenameChange(path: "/documents/One", name: "First"),
                FileStationRenameChange(path: "/documents/Two", name: "Second"),
            ],
            searchTaskID: "search-1"
        )

        #expect(created.map(\.name) == ["One", "Two"])
        #expect(renamed.map(\.name) == ["First", "Second"])
        let requests = await stub.requests
        let create = try query(from: requests[0])
        #expect(create["force_parent"] == "true")
        #expect(try decodeStrings(create["folder_path"]) == ["/documents", "/documents"])
        #expect(try decodeStrings(create["name"]) == ["One", "Two"])
        let rename = try query(from: requests[1])
        #expect(rename["search_taskid"] == "search-1")
        #expect(try decodeStrings(rename["path"]) == ["/documents/One", "/documents/Two"])
    }

    @Test func supportsTheSharingLinkLifecycle() async throws {
        let link = #"{"date_available":"0","date_expired":"0","has_password":false,"id":"link-1","isFolder":false,"link_owner":"admin","name":"report.pdf","path":"/documents/report.pdf","status":"valid","url":"https://nas.example/s/link-1"}"#
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":\#(link)}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"total":1,"offset":0,"links":[\#(link)]}}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"links":[{"error":0,"id":"link-2","path":"/documents/notes.txt","qrcode":"abc","url":"https://nas.example/s/link-2"}]}}"#.utf8
            )),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.Sharing": entry(maxVersion: 3)]
        )

        let information = try await service.shareLinkInformation(id: "link-1")
        let page = try await service.shareLinks(
            options: FileStationSharingListOptions(
                limit: 10,
                sortBy: .expirationDate,
                sortDirection: .descending,
                forceRefresh: true
            )
        )
        let created = try await service.createShareLinks(
            FileStationShareLinkCreation(
                paths: ["/documents/notes.txt"],
                password: "secret",
                expirationDate: "2026-12-31",
                availableDate: "2026-07-20"
            )
        )
        try await service.editShareLinks(
            ids: ["link-1"],
            changes: FileStationShareLinkChanges(password: "", expirationDate: "0")
        )
        try await service.deleteShareLinks(ids: ["link-1", "link-2"])
        try await service.clearInvalidShareLinks()

        #expect(information.owner == "admin")
        #expect(page.total == 1)
        #expect(created.first?.qrCode == "abc")
        let requests = await stub.requests
        let list = try query(from: requests[1])
        #expect(list["sort_by"] == "date_expired")
        #expect(list["force_clean"] == "true")
        let create = try query(from: requests[2])
        #expect(create["date_available"] == "2026-07-20")
        let edit = try query(from: requests[3])
        #expect(edit["password"] == "")
        #expect(edit["date_expired"] == "0")
        let delete = try query(from: requests[4])
        #expect(try decodeStrings(delete["id"]) == ["link-1", "link-2"])
        #expect(try query(from: requests[5])["method"] == "clear_invalid")
    }

    @Test func listsArchivesAndUsesAllCompressionAndExtractionOptions() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"total":"1","items":[{"itemid":"7","name":"docs","size":"4096","pack_size":"1024","mtime":"2026-07-19 12:00:00","path":"docs","is_dir":"true"}]}}"#.utf8
            )),
            .response(Data(#"{"success":true,"data":{"taskid":"compress-1"}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"finished":true,"dest_file_path":"/documents/archive.7z"}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"taskid":"extract-1"}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"finished":true,"progress":1,"dest_folder_path":"/documents/output"}}"#.utf8)),
        ])
        let service = makeService(
            stub: stub,
            entries: [
                "SYNO.FileStation.Extract": entry(maxVersion: 2),
                "SYNO.FileStation.Compress": entry(maxVersion: 3),
            ]
        )

        let archive = try await service.archiveItems(
            archivePath: "/documents/archive.7z",
            options: FileStationArchiveListOptions(
                sortBy: .packedSize,
                sortDirection: .descending,
                codepage: .english,
                password: "secret",
                parentItemID: 7
            )
        )
        try await service.compress(
            paths: ["/documents/docs"],
            to: "/documents/archive.7z",
            options: FileStationCompressionOptions(
                level: .best,
                mode: .synchronize,
                format: .sevenZip,
                password: "secret"
            )
        )
        try await service.extract(
            archivePath: "/documents/archive.7z",
            to: "/documents/output",
            options: FileStationExtractionOptions(
                conflictPolicy: .overwrite,
                keepsDirectoryStructure: false,
                createsSubfolder: true,
                codepage: .english,
                password: "secret",
                itemIDs: [7]
            )
        )

        #expect(archive.elements.first?.itemID == 7)
        #expect(archive.elements.first?.isDirectory == true)
        let requests = await stub.requests
        let list = try query(from: requests[0])
        #expect(list["sort_by"] == "pack_size")
        #expect(list["item_id"] == "7")
        let compress = try query(from: requests[1])
        #expect(compress["level"] == "best")
        #expect(compress["mode"] == "synchronize")
        #expect(compress["format"] == "7z")
        let extract = try query(from: requests[3])
        #expect(extract["overwrite"] == "true")
        #expect(extract["keep_dir"] == "false")
        #expect(extract["create_subfolder"] == "true")
        let itemIDs = try #require(extract["item_id"])
        #expect(try JSONDecoder().decode([Int].self, from: Data(itemIDs.utf8)) == [7])
    }

    @Test func returnsBinaryThumbnailData() async throws {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let stub = DSMRequestStub(results: [
            .HTTPResponse(data: imageData, statusCode: 200, contentType: "image/png"),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.Thumb": entry(maxVersion: 2)]
        )

        let data = try await service.thumbnail(
            path: "/photo/image.png",
            size: .large,
            rotation: .clockwise90
        )

        #expect(data == imageData)
        let request = try query(from: try #require(await stub.requests.first))
        #expect(request["size"] == "large")
        #expect(request["rotate"] == "1")
    }

    @Test func uploadsWithVersionThreeConflictAndTimestampFields() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.Upload": entry(maxVersion: 3)]
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "upload-\(UUID().uuidString).txt")
        try Data("contents".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try await service.upload(
            fileURL: fileURL,
            to: "/documents",
            options: FileStationUploadOptions(
                conflictPolicy: .skip,
                createParentFolders: false,
                modificationDate: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )

        let request = try #require(await stub.requests.first)
        #expect(request.httpMethod == "POST")
        let bodyData = try #require(await stub.uploadedBodies.first)
        let body = try #require(String(data: bodyData, encoding: .utf8))
        #expect(body.contains("name=\"version\"\r\n\r\n3"))
        #expect(body.contains("name=\"path\"\r\n\r\n/documents"))
        #expect(body.contains("name=\"overwrite\"\r\n\r\nskip"))
        #expect(body.contains("name=\"create_parents\"\r\n\r\nfalse"))
        #expect(body.contains("name=\"mtime\"\r\n\r\n1700000000000"))
        #expect(body.contains("name=\"file\"; filename=\"\(fileURL.lastPathComponent)\""))
    }

    @Test func downloadsMultiplePathsAsOneArchive() async throws {
        let archiveData = Data("zip-data".utf8)
        let stub = DSMRequestStub(results: [
            .HTTPResponse(
                data: archiveData,
                statusCode: 200,
                contentType: "application/octet-stream"
            ),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.Download": entry(maxVersion: 2)]
        )
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "download-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destination) }

        try await service.download(
            paths: ["/documents/one.txt", "/documents/two.txt"],
            to: destination
        )

        #expect(try Data(contentsOf: destination) == archiveData)
        let request = try query(from: try #require(await stub.requests.first))
        #expect(request["mode"] == "download")
        #expect(
            try decodeStrings(request["path"])
                == ["/documents/one.txt", "/documents/two.txt"]
        )
    }

    @Test func reportsAFailedShareLinkWithoutRequiringMissingSuccessFields() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"links":[{"error":2002,"path":"/documents/report.pdf"}]}}"#.utf8
            )),
        ])
        let service = makeService(
            stub: stub,
            entries: ["SYNO.FileStation.Sharing": entry(maxVersion: 3)]
        )

        await #expect(
            throws: DSMError.itemOperationFailed(
                code: 2002,
                item: "/documents/report.pdf",
                itemCode: 2002
            )
        ) {
            _ = try await service.createShareLinks(
                FileStationShareLinkCreation(paths: ["/documents/report.pdf"])
            )
        }
    }

    private func makeService(
        stub: DSMRequestStub,
        entries: [String: APIInfoEntry]
    ) -> DSMFileStationService {
        var capabilities = DSMCapabilities()
        capabilities.merge(entries)
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) },
            downloadFile: { try await stub.download(from: $0) },
            uploadFile: { try await stub.upload(for: $0, fromFile: $1) }
        )
        transport.establishSession(LoginResult(sid: "session-id", did: nil, synotoken: nil))
        return DSMFileStationService(
            transport: transport,
            operationPollInterval: .zero,
            operationPollLimit: 4
        )
    }

    private func entry(maxVersion: Int) -> APIInfoEntry {
        APIInfoEntry(path: "entry.cgi", minVersion: 1, maxVersion: maxVersion)
    }

    private func query(from request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    private func decodeStrings(_ value: String?) throws -> [String] {
        let value = try #require(value)
        return try JSONDecoder().decode([String].self, from: Data(value.utf8))
    }
}
