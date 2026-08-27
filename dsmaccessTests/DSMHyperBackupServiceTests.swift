import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMHyperBackupServiceTests {
    /// `SYNO.Backup.Task` publishes versions 1 and 2, but only version 1 answers `list`.
    /// Taking the advertised maximum would silently break the module.
    @Test func listsTasksOnVersionOneEvenWhenTwoIsAdvertised() async throws {
        let response = Data(
            #"""
            {"success":true,"data":{"total":1,"is_restoring":false,"task_list":[
              {"task_id":7,"name":"dsmaccess-test","repo_id":7,"target_id":"dsmaccess-test.hbk",
               "target_type":"image","transfer_type":"image_local","type":"image:image_local",
               "state":"backupable","status":"none","data_type":"data","data_enc":false}]}}
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let tasks = try await service.tasks()

        let task = try #require(tasks.first)
        #expect(task.taskID == 7)
        #expect(task.name == "dsmaccess-test")
        #expect(task.knownStatus == .idle)
        #expect(!task.isEncrypted)
        #expect(!task.isRunning)
        #expect(task.canBackUp)

        let parameters = try query(from: #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Backup.Task")
        #expect(parameters["method"] == "list")
        #expect(parameters["version"] == "1")
    }

    /// The mirror image: `SYNO.Backup.Version` only lists on version 2.
    @Test func listsVersionsOnVersionTwo() async throws {
        let response = Data(
            #"""
            {"success":true,"data":{"total":2,"version_info_list":[
              {"version_id":"1","status":"success","locked":false,"has_history":true,
               "permit_delete":true,"timestamp":1785724175,"complete_time":1785724238},
              {"version_id":"4","status":"cancel","locked":true,"has_history":false,
               "permit_delete":false,"timestamp":1785726121,"complete_time":1785726133}]}}
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let versions = try await service.versions(taskID: 7)

        #expect(versions.count == 2)
        let first = try #require(versions.first)
        // DSM sends the identifier as a string even though it reads as a number.
        #expect(first.versionID == "1")
        #expect(first.knownStatus == .success)
        #expect(first.completionDate == Date(timeIntervalSince1970: 1_785_724_238))
        let cancelled = try #require(versions.last)
        #expect(cancelled.knownStatus == .cancelled)
        #expect(cancelled.isLocked)
        #expect(!cancelled.canDelete)

        let parameters = try query(from: #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Backup.Version")
        #expect(parameters["method"] == "list")
        #expect(parameters["version"] == "2")
    }

    /// Sizes and counters come back as strings in the progress block.
    @Test func decodesProgressCountersSentAsStrings() async throws {
        let response = Data(
            #"""
            {"success":true,"data":{"task_id":7,"state":"backupable","status":"backup",
              "progress":{"step":"data_backup","title_type":"backingup","progress":42,
                "show_progress":true,"can_cancel":true,"can_suspend":true,"avg_speed":0,
                "total_size":"1284","processed_size":"640","transmitted_size":"512",
                "scan_file_count":"3","counted_file_count":"2","current_app":"",
                "app_list":[],"app_done_list":[]}}}
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let state = try await service.state(taskID: 7)

        let progress = try #require(state.progress)
        #expect(progress.totalSize == 1284)
        #expect(progress.processedSize == 640)
        #expect(progress.transmittedSize == 512)
        #expect(progress.scannedFileCount == 3)
        #expect(progress.countedFileCount == 2)
        #expect(progress.percentage == 42)
        #expect(progress.canCancel)
        #expect(progress.knownStep == .data)
        // An empty current application is an absence, not a name.
        #expect(progress.currentApplication == nil)
    }

    /// Cancelling requires `task_state` next to the identifier: sending only `task_id`
    /// is refused with error 4400 even while DSM reports the run as cancellable.
    /// These APIs advertise `requestFormat: JSON`, so the state travels quoted — a form the
    /// NAS was verified to accept.
    @Test func cancellingSendsTheTaskStateAlongsideTheIdentifier() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.cancel(taskID: 7, state: "backupable")

        let parameters = try query(from: #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Backup.Task")
        #expect(parameters["method"] == "cancel")
        #expect(parameters["task_id"] == "7")
        #expect(parameters["task_state"] == #""backupable""#)
    }

    @Test func startingABackupOnlySendsTheIdentifier() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.backUp(taskID: 7)

        let parameters = try query(from: #require(await stub.requests.first))
        #expect(parameters["method"] == "backup")
        #expect(parameters["task_id"] == "7")
        #expect(parameters["task_state"] == nil)
    }

    @Test func readsWhatTheDestinationSupports() async throws {
        let response = Data(
            #"""
            {"success":true,"data":{"capability":{"support_download":true,"support_filter":false,
              "support_statistics":true},"data_comp":true,"data_enc":false,"format_type":"hbk",
              "host_name":"local","support_multi_version":true,"last_detect_time":0}}
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let target = try await service.target(taskID: 7)

        #expect(target.capability?.supportsStatistics == true)
        #expect(target.capability?.supportsFilter == false)
        #expect(target.supportsMultipleVersions)
        // A zero timestamp means "never checked", not 1970.
        #expect(target.lastIntegrityCheckDate == nil)
    }

    @Test func decodesTheTaskLogWithItsCounters() async throws {
        let response = Data(
            #"""
            {"success":true,"data":{"total":3,"offset":0,"error_count":2,"warn_count":0,
              "info_count":1,"log_list":[
                {"event":"[Local][dsmaccess-test] Backup task was cancelled.","level":"err",
                 "time":"2026/08/03 04:42:19","user":"nasuser"},
                {"event":"[Local][dsmaccess-test] Backup task started.","level":"info",
                 "time":"2026/08/03 04:42:01","user":"nasuser"}]}}
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let page = try await service.logs(taskID: 7, offset: 0, limit: 200)

        #expect(page.total == 3)
        #expect(page.errorCount == 2)
        let first = try #require(page.entries.first)
        #expect(first.knownLevel == .error)
        #expect(first.date != nil)
        let last = try #require(page.entries.last)
        #expect(last.knownLevel == .information)
    }

    /// DSM returns the previous run and the latest one side by side; a run whose `end_time`
    /// is zero simply does not exist and must not be shown as a backup dated 1970.
    @Test func ignoresTheAbsentPreviousRunInStatistics() async throws {
        let response = Data(
            #"""
            {"success":true,"data":{"source_list":[],"target_list":[],
              "source_previous_next_list":[
                {"delete_count":0,"end_time":0,"modify_count":0,"new_count":0,"source_size":0},
                {"delete_count":0,"end_time":1785724246,"modify_count":0,"new_count":2,"source_size":1284}],
              "target_previous_next_list":[
                {"end_time":0,"target_size":0},
                {"end_time":1785724901,"target_size":3379}]}}
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let statistics = try await service.statistics(taskID: 7)

        #expect(statistics.previousRun == nil)
        let latest = try #require(statistics.latestRun)
        #expect(latest.newCount == 2)
        #expect(latest.sourceSize == 1284)
        #expect(latest.targetSize == 3379)
    }

    /// The cancel affordance follows DSM's own `can_cancel`, never the status alone: a task
    /// reported as running without a progress block offers nothing to cancel.
    @Test func cancelAffordanceFollowsTheServerFlagRatherThanTheStatus() throws {
        let listing = Data(
            #"""
            {"total":1,"task_list":[{"task_id":7,"name":"t","repo_id":7,"target_id":"t.hbk",
              "target_type":"image","transfer_type":"image_local","type":"image:image_local",
              "state":"backupable","status":"backup","data_enc":false}]}
            """#.utf8
        )
        var task = try #require(
            try JSONDecoder().decode(HyperBackupTaskList.self, from: listing).tasks.first
        )
        #expect(task.isRunning)
        #expect(!task.canCancel)
        #expect(!task.canBackUp)

        let state = Data(
            #"""
            {"task_id":7,"state":"backupable","status":"backup",
             "progress":{"step":"data_backup","progress":0,"show_progress":false,
               "can_cancel":true,"can_suspend":false}}
            """#.utf8
        )
        task.liveState = try JSONDecoder().decode(HyperBackupTaskState.self, from: state)
        #expect(task.canCancel)
    }

    /// An unmeasured stage or status keeps its raw DSM wording instead of being folded into
    /// a neighbouring case.
    @Test func unknownStatusAndStepKeepTheirRawWording() throws {
        let listing = Data(
            #"""
            {"total":1,"task_list":[{"task_id":9,"name":"t","repo_id":1,"target_id":"t.hbk",
              "target_type":"image","transfer_type":"carrier_pigeon","type":"image:pigeon",
              "state":"backupable","status":"defragmenting","data_enc":true}]}
            """#.utf8
        )
        let task = try #require(
            try JSONDecoder().decode(HyperBackupTaskList.self, from: listing).tasks.first
        )

        #expect(task.knownStatus == nil)
        #expect(task.statusDescription == "defragmenting")
        #expect(task.destinationDescription == "carrier_pigeon")
        #expect(task.isEncrypted)
    }

    /// The root of a version comes from `Folder.list`, which answers a bare array rather than
    /// a wrapped list, and refuses to answer at all without the version.
    @Test func listsBackupRootFromBareArray() async throws {
        let response = Data(
            #"""
            {"success":true,"data":[
              {"name":"Test","path":"Test","type":"Folder","size":0,"mtime":0,
               "is_bad":false,"restore_unsafe_warn":false}]}
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let entries = try await service.backupRoot(taskID: 7, versionID: "3")

        let entry = try #require(entries.first)
        #expect(entry.name == "Test")
        #expect(entry.isFolder)

        let parameters = try query(from: #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.SDS.Backup.Client.Explore.Folder")
        #expect(parameters["method"] == "list")
        #expect(parameters["version_id"] == "\"3\"")
    }

    /// Listing a folder needs `node`, and the path it carries has no leading slash: `/Test`
    /// is refused where `Test` is accepted.
    @Test func listsFolderContentsWithRelativeNode() async throws {
        let response = Data(
            #"""
            {"success":true,"data":{"total":2,"files":[
              {"name":"temoin-un.txt","path":"Test/essai/temoin-un.txt","type":"File",
               "size":69,"mtime":1785723573,"is_bad":false,"restore_unsafe_warn":false},
              {"name":"casse.txt","path":"Test/essai/casse.txt","type":"File",
               "size":12,"mtime":1785723573,"is_bad":true,"restore_unsafe_warn":false}]}}
            """#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let entries = try await service.backupEntries(taskID: 7, versionID: "3", node: "Test/essai")

        #expect(entries.count == 2)
        let file = try #require(entries.first)
        #expect(!file.isFolder)
        #expect(file.size == 69)
        // Damage is written out, never carried by an icon alone.
        #expect(try #require(entries.last).isDamaged)

        let parameters = try query(from: #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.SDS.Backup.Client.Explore.File")
        let node = try jsonString(#require(parameters["node"]))
        #expect(node == "Test/essai")
        // Relative to the backup root: a leading slash is answered with error 4400.
        #expect(!node.hasPrefix("/"))
    }

    /// The parameter the whole feature hangs on. `copy` answers error 4401 without `backend`,
    /// whatever else the request carries, and DSM reports that failure as a network problem —
    /// so losing this field would look like a broken NAS rather than a broken request.
    @Test func copyCarriesTheBackendTheEngineDemands() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.copyFromBackup(
            taskID: 7,
            versionID: "3",
            node: "Test",
            sourcePaths: ["Test/dsmaccess-restore-test"],
            destinationPath: "/volume1/Documents",
            overwrite: false
        )

        let parameters = try query(from: #require(await stub.requests.first))
        #expect(parameters["method"] == "copy")
        #expect(try jsonString(#require(parameters["backend"])) == "HyperBackup-backend")
        #expect(try jsonString(#require(parameters["action"])) == "copy")
        let sources = try JSONDecoder().decode(
            [String].self,
            from: Data(#require(parameters["source_path"]).utf8)
        )
        #expect(sources == ["Test/dsmaccess-restore-test"])
        // The physical volume path, never the `/Documents` share path, which is refused.
        #expect(try jsonString(#require(parameters["dest_path"])) == "/volume1/Documents")
        #expect(parameters["overwrite"] == "false")
    }

    /// Restoring in place is the one operation that writes over the user's own files, and it
    /// differs from `copy` on every point that matters: relative paths instead of a physical
    /// one, and `overwrite` forced rather than chosen. Values measured on the NAS by
    /// intercepting the DSM explorer's own "Restaurer" button.
    @Test func restoreInPlaceKeepsRelativePathsAndForcesOverwrite() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.restoreInPlaceFromBackup(
            taskID: 7,
            versionID: "3",
            node: "Test",
            sourcePaths: ["Test/dsmaccess-restore-test"],
            originPath: "Test/dsmaccess-restore-test"
        )

        let parameters = try query(from: #require(await stub.requests.first))
        #expect(parameters["method"] == "restore")
        #expect(try jsonString(#require(parameters["action"])) == "restore")
        // The explorer sends `backend` on every request, this one included.
        #expect(try jsonString(#require(parameters["backend"])) == "HyperBackup-backend")
        // Relative to the backup root, unlike `copy` which insists on `/volume1/…`.
        #expect(try jsonString(#require(parameters["dest_path"])) == "Test/dsmaccess-restore-test")
        #expect(parameters["overwrite"] == "true")
    }

    /// The download URL is built rather than posted, and two of its details come from the DSM
    /// client alone: the file name sits in the CGI path, and `source_path` is a single string
    /// where the other explorer mutations take an array.
    @Test func downloadNamesTheFileInThePathAndSendsOneSourcePath() async throws {
        let stub = DSMRequestStub(results: [])
        let service = makeService(stub: stub)

        let url = try await service.backupDownloadURL(
            taskID: 7,
            versionID: "3",
            node: "Test/dsmaccess-restore-test",
            sourcePath: "Test/dsmaccess-restore-test/temoin-un.txt",
            fileName: "temoin-un.txt"
        )

        #expect(url.path().hasSuffix("/temoin-un.txt"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let parameters = Dictionary(items.map { ($0.name, $0.value ?? "") }) { first, _ in first }
        #expect(parameters["method"] == "download")
        #expect(try jsonString(#require(parameters["backend"])) == "HyperBackup-backend")
        // A lone path, never a JSON array: DSM downloads one entry at a time.
        #expect(try jsonString(#require(parameters["source_path"])) == "Test/dsmaccess-restore-test/temoin-un.txt")
        #expect(parameters["support_utf8_name"] == "true")
        #expect(try !jsonString(#require(parameters["download_id"])).isEmpty)
    }

    /// Strings travel JSON-encoded because these APIs advertise `requestFormat: JSON`, which
    /// also escapes the slashes inside paths. Comparing decoded values keeps the tests about
    /// the contract rather than about the encoder's punctuation.
    private func jsonString(_ raw: String) throws -> String {
        try JSONDecoder().decode(String.self, from: Data(raw.utf8))
    }

    private func makeService(stub: DSMRequestStub) -> DSMHyperBackupService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Backup.Task": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 2,
                requestFormat: "JSON"
            ),
            "SYNO.Backup.Target": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 2,
                requestFormat: "JSON"
            ),
            "SYNO.Backup.Version": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 2,
                requestFormat: "JSON"
            ),
            "SYNO.SDS.Backup.Client.Common.Log": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.SDS.Backup.Client.Common.Statistic": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.SDS.Backup.Client.Explore.Folder": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.SDS.Backup.Client.Explore.File": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
        ])
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) }
        )
        transport.establishSession(LoginResult(sid: "session-id", did: nil, synotoken: nil))
        return DSMHyperBackupService(transport: transport)
    }

    /// The restore browser reads these values column by column. A missing one is nil: how an
    /// absence looks, and whether it is spoken, belongs to the cell that draws it — a condition
    /// column would otherwise say a dash on every healthy row.
    @Test func describesTheColumnsOfABackupEntry() throws {
        let decoder = JSONDecoder()
        let file = try decoder.decode(
            HyperBackupEntry.self,
            from: Data(
                #"{"name":"rapport.pdf","path":"Test/rapport.pdf","type":"File","size":4096,"mtime":1710000000}"#.utf8
            )
        )
        let folder = try decoder.decode(
            HyperBackupEntry.self,
            from: Data(#"{"name":"Test","path":"Test","type":"Folder","size":4096,"mtime":1710000000}"#.utf8)
        )
        let damaged = try decoder.decode(
            HyperBackupEntry.self,
            from: Data(#"{"name":"casse.txt","path":"Test/casse.txt","type":"File","is_bad":true}"#.utf8)
        )

        #expect(file.sizeDescription != nil)
        #expect(file.modificationDescription != nil)
        #expect(file.warningDescription == nil)
        // A folder's own record size says nothing about what it holds.
        #expect(folder.sizeDescription == nil)
        #expect(folder.modificationDescription != nil)
        #expect(damaged.sizeDescription == nil)
        #expect(damaged.modificationDescription == nil)
        #expect(damaged.warningDescription == String(localized: "hyper_backup.restore.condition.damaged"))
    }

    private func query(from request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
