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
            requestData: { try await stub.data(for: $0) }
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
}
