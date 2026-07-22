import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMUSBCopyServiceTests {
    @Test func listsTasksWithTheDiscoveredMaximumVersion() async throws {
        let response = Data(
            #"{"success":true,"data":{"tasks":[{"id":1,"name":"Media Export","type":"export_general","source_path":"/Media","destination_path":"[USB]","copy_strategy":"mirror","status":"unmounted","is_task_runnable":false,"is_default_task":false}]}}"#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let tasks = try await service.tasks()

        let task = try #require(tasks.first)
        #expect(task.id == 1)
        #expect(task.name == "Media Export")
        #expect(task.knownType == .exportGeneral)
        #expect(task.knownStrategy == .mirror)
        #expect(task.knownStatus == .unmounted)
        #expect(!task.canDisable)
        #expect(task.canDelete)

        let requests = await stub.requests
        let request = try #require(requests.first)
        let parameters = try query(from: request)
        #expect(parameters["api"] == "SYNO.USBCopy")
        #expect(parameters["version"] == "1")
        #expect(parameters["method"] == "list")
    }

    @Test func createsACompleteTaskInsideTheTaskParameter() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"task_id":42}}"#.utf8)),
        ])
        let service = makeService(stub: stub)
        let creation = USBCopyTaskCreation(
            type: .exportGeneral,
            name: "Archive USB",
            sourcePath: "/Documents",
            destinationPath: "/usbshare1/Archive",
            copyStrategy: .versioning,
            enableRotation: true,
            rotationPolicy: .smartRecycle,
            maxVersionCount: 32,
            removeSourceFile: false,
            notKeepDirectoryStructure: nil,
            smartCreateDateDirectory: nil,
            renamePhotoVideo: nil,
            conflictPolicy: nil,
            runWhenPlugIn: true,
            ejectWhenTaskDone: true,
            scheduleEnabled: false,
            scheduleContent: .defaultValue,
            filter: .defaultValue(for: .exportGeneral)
        )

        let taskID = try await service.create(creation)

        #expect(taskID == 42)
        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "create")
        let task = try #require(parameters["task"]).jsonDictionary
        #expect(task["type"] as? String == "export_general")
        #expect(task["source_path"] as? String == "/Documents")
        #expect(task["destination_path"] as? String == "/usbshare1/Archive")
        #expect(task["copy_strategy"] as? String == "versioning")
        #expect(task["enable_rotation"] as? Bool == true)
        #expect(task["max_version_count"] as? Int == 32)
        #expect(task["schedule_content"] as? [String: Any] != nil)
        #expect(task["filter"] as? [String: Any] != nil)
    }

    @Test func neverRetriesACreateAfterTimeout() async {
        let stub = DSMRequestStub(results: [.timeout, .response(Data(#"{"success":true,"data":{"task_id":8}}"#.utf8))])
        let service = makeService(stub: stub)
        let creation = USBCopyTaskCreation(
            type: .importPhoto,
            name: "Photos",
            sourcePath: "/usbshare1/DCIM",
            destinationPath: "/photo",
            copyStrategy: .incremental,
            enableRotation: nil,
            rotationPolicy: nil,
            maxVersionCount: nil,
            removeSourceFile: false,
            notKeepDirectoryStructure: true,
            smartCreateDateDirectory: true,
            renamePhotoVideo: true,
            conflictPolicy: .rename,
            runWhenPlugIn: true,
            ejectWhenTaskDone: true,
            scheduleEnabled: false,
            scheduleContent: .defaultValue,
            filter: .defaultValue(for: .importPhoto)
        )

        await #expect(throws: DSMError.self) {
            _ = try await service.create(creation)
        }
        #expect(await stub.requestCount == 1)
    }

    @Test func photoImportCreationUsesThePackageRequiredConfiguration() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"task_id":9}}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)
        let creation = USBCopyTaskCreation(
            type: .importPhoto,
            name: "Photos",
            sourcePath: "/usbshare1/DCIM",
            destinationPath: "/photo",
            copyStrategy: .versioning,
            enableRotation: true,
            rotationPolicy: .smartRecycle,
            maxVersionCount: 8,
            removeSourceFile: false,
            notKeepDirectoryStructure: false,
            smartCreateDateDirectory: false,
            renamePhotoVideo: false,
            conflictPolicy: .overwrite,
            runWhenPlugIn: false,
            ejectWhenTaskDone: false,
            scheduleEnabled: true,
            scheduleContent: .defaultValue,
            filter: .defaultValue(for: .importPhoto)
        )

        _ = try await service.create(creation)

        let request = try #require(await stub.requests.first)
        let creationQuery = try query(from: request)
        let task = try #require(creationQuery["task"]).jsonDictionary
        #expect(task["copy_strategy"] as? String == "incremental")
        #expect(task["not_keep_dir_structure"] as? Bool == true)
        #expect(task["smart_create_date_dir"] as? Bool == true)
        #expect(task["rename_photo_video"] as? Bool == true)
        #expect(task["conflict_policy"] as? String == "rename")
        #expect(task["schedule_enabled"] as? Bool == false)
        #expect(task["enable_rotation"] == nil)
        #expect(task["rotation_policy"] == nil)
        #expect(task["max_version_count"] == nil)

        try await service.setSettings(USBCopyTaskSettings(
            id: 9,
            type: .importPhoto,
            name: "Photos",
            sourcePath: "/usbshare1/DCIM",
            destinationPath: "/photo",
            copyStrategy: .mirror,
            enableRotation: true,
            rotationPolicy: .smartRecycle,
            maxVersionCount: 8,
            removeSourceFile: false,
            notKeepDirectoryStructure: false,
            smartCreateDateDirectory: false,
            renamePhotoVideo: false,
            conflictPolicy: .overwrite
        ))
        let settingsRequest = try #require(await stub.requests.last)
        let settingsQuery = try query(from: settingsRequest)
        let settings = try #require(settingsQuery["task_setting"]).jsonDictionary
        #expect(settings["copy_strategy"] as? String == "incremental")
        #expect(settings["enable_rotation"] as? Bool == false)
        #expect(settings["not_keep_dir_structure"] as? Bool == true)
        #expect(settings["smart_create_date_dir"] as? Bool == true)
        #expect(settings["rename_photo_video"] as? Bool == true)
        #expect(settings["conflict_policy"] as? String == "rename")
    }

    @Test func sendsSettingsFilterAndTriggerWithTheirObservedParameterNames() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"schedule_id":7,"next_run_time":"N/A"}}"#.utf8)),
        ])
        let service = makeService(stub: stub)
        let settings = USBCopyTaskSettings(
            id: 3,
            type: .importGeneral,
            name: "Import",
            sourcePath: "/usbshare1",
            destinationPath: "/Archive",
            copyStrategy: .incremental,
            enableRotation: false,
            rotationPolicy: .oldestVersion,
            maxVersionCount: 256,
            removeSourceFile: true,
            notKeepDirectoryStructure: true,
            smartCreateDateDirectory: false,
            renamePhotoVideo: true,
            conflictPolicy: .rename
        )
        let filter = USBCopyFilter.defaultValue(for: .importGeneral)
        let trigger = USBCopyTrigger(
            runWhenPlugIn: true,
            ejectWhenTaskDone: false,
            scheduleEnabled: true,
            scheduleContent: .defaultValue
        )

        try await service.setSettings(settings)
        try await service.setFilter(filter, taskID: 3)
        let triggerResult = try await service.setTrigger(trigger, taskID: 3)

        #expect(triggerResult.scheduleID == 7)
        let requests = await stub.requests
        #expect(requests.count == 3)
        let settingQuery = try query(from: requests[0])
        #expect(settingQuery["method"] == "set_setting")
        #expect(settingQuery["id"] == "3")
        #expect(try #require(settingQuery["task_setting"]).jsonDictionary["remove_src_file"] as? Bool == true)
        let filterQuery = try query(from: requests[1])
        #expect(filterQuery["method"] == "set_filter")
        #expect(filterQuery["task_filter"] != nil)
        let triggerQuery = try query(from: requests[2])
        #expect(triggerQuery["method"] == "set_trigger_time")
        #expect(try #require(triggerQuery["trigger_time"]).jsonDictionary["schedule_enabled"] as? Bool == true)
    }

    @Test func readsTheTaskScheduleThroughTaskSchedulerVersionTwo() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"task":{"id":4,"name":"Weekly Export","type":"export_general","source_path":"/Media","destination_path":"[USB]","copy_strategy":"versioning","status":"successful","schedule_id":9,"run_when_plug_in":true,"eject_when_task_done":false}}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"enable":true,"schedule":{"date_type":0,"week_day":"1,3,5","date":"2026/07/22","repeat_date":0,"hour":23,"minute":30,"repeat_hour":0,"last_work_hour":0}}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let task = try await service.task(id: 4)
        let trigger = try await service.trigger(for: task)

        #expect(trigger.runWhenPlugIn)
        #expect(!trigger.ejectWhenTaskDone)
        #expect(trigger.scheduleEnabled)
        #expect(trigger.scheduleContent.weekDay == "1,3,5")
        #expect(trigger.scheduleContent.hour == 23)

        let requests = await stub.requests
        #expect(requests.count == 2)
        let taskQuery = try query(from: requests[0])
        #expect(taskQuery["api"] == "SYNO.USBCopy")
        #expect(taskQuery["method"] == "get")
        #expect(taskQuery["id"] == "4")
        let scheduleQuery = try query(from: requests[1])
        #expect(scheduleQuery["api"] == "SYNO.Core.TaskScheduler")
        #expect(scheduleQuery["version"] == "2")
        #expect(scheduleQuery["method"] == "get")
        #expect(scheduleQuery["id"] == "9")
    }

    @Test func sendsEveryTaskActionWithTheTaskIdentifier() async throws {
        let success = Data(#"{"success":true}"#.utf8)
        let stub = DSMRequestStub(results: Array(repeating: .response(success), count: 5))
        let service = makeService(stub: stub)

        try await service.run(taskID: 6)
        try await service.cancel(taskID: 6)
        try await service.enable(taskID: 6)
        try await service.disable(taskID: 6)
        try await service.delete(taskID: 6)

        let requests = await stub.requests
        #expect(requests.count == 5)
        let queries = try requests.map(query(from:))
        #expect(queries.compactMap { $0["method"] } == ["run", "cancel", "enable", "disable", "delete"])
        #expect(queries.allSatisfy { $0["id"] == "6" })
    }

    @Test func readsGlobalSettingsLogsAndExternalShareMetadata() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"repo_volume_path":"/volume1","log_rotate_count":100000,"beep_on_task_start_end":true}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"count":1,"log_list":[{"description_id":101,"description_parameter":"\"Backup\"","error":"","log_type":1,"task_id":1,"timestamp":1782302241}]}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"shares":[{"name":"Files","external_dev_type":""},{"name":"usbshare1","external_dev_type":"USB"}]}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"volumes":[{"volume_path":"/volume1","size_total_byte":"1000"},{"volume_path":"/volume2","size_total_byte":0}]}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let settings = try await service.globalSettings()
        let page = try await service.logs(offset: 0, limit: 200, filter: .all)
        let shares = try await service.availableShares()
        let volumePaths = try await service.availableVolumePaths()

        #expect(settings.repositoryVolumePath == "/volume1")
        #expect(settings.logRotateCount == 100_000)
        #expect(page.count == 1)
        #expect(page.logList.first?.descriptionID == 101)
        #expect(shares.last?.externalDeviceType == "USB")
        #expect(volumePaths == ["/volume1"])

        let requests = await stub.requests
        let logQuery = try query(from: requests[1])
        #expect(logQuery["method"] == "get_log_list")
        #expect(logQuery["offset"] == "0")
        #expect(logQuery["limit"] == "200")
        let logFilter = try #require(logQuery["log_filter"]).jsonDictionary
        #expect(Set(logFilter.keys) == ["log_desc_id_list", "log_type"])
        #expect((logFilter["log_desc_id_list"] as? [Int])?.count == 13)
        #expect(logFilter["log_type"] as? Int == USBCopyLogType.all.rawValue)
        let shareQuery = try query(from: requests[2])
        #expect(shareQuery["api"] == "SYNO.Core.Share")
        #expect(shareQuery["shareType"] == #"["local","usb","dec","c2"]"#)
        let volumeQuery = try query(from: requests[3])
        #expect(volumeQuery["api"] == "SYNO.Core.Storage.Volume")
        #expect(volumeQuery["method"] == "list")
        #expect(volumeQuery["limit"] == "-1")
        #expect(volumeQuery["location"] == #""internal""#)
    }

    @Test func logRequestUsesTheConfirmedSearchFieldNames() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"count":0,"log_list":[]}}"#.utf8)),
        ])
        let service = makeService(stub: stub)
        let filter = USBCopyLogFilter(
            descriptionIDs: [100, 103],
            keyword: "Backup",
            fromTimestamp: 1_700_000_000,
            toTimestamp: 1_700_086_399,
            logType: USBCopyLogType.error.rawValue
        )

        _ = try await service.logs(offset: 4, limit: 20, filter: filter)

        let request = try #require(await stub.requests.first)
        let query = try query(from: request)
        let logFilter = try #require(query["log_filter"]).jsonDictionary
        #expect(logFilter["log_desc_id_list"] as? [Int] == [100, 103])
        #expect(logFilter["key_word"] as? String == "Backup")
        #expect(logFilter["from_timestamp"] as? Int == 1_700_000_000)
        #expect(logFilter["to_timestamp"] as? Int == 1_700_086_399)
        #expect(logFilter["log_type"] as? Int == USBCopyLogType.error.rawValue)
    }

    @Test func filterSelectionPreservesTheWildcardAndExcludedBuiltInTypes() {
        var selection = USBCopyFilterSelection(filter: .defaultValue(for: .exportGeneral))
        selection.selectedExtensions.remove("mp3")
        selection.customExtensions = ["abc"]
        selection.customNames = ["README"]

        let filter = selection.filter
        let restored = USBCopyFilterSelection(filter: filter)

        #expect(filter.whiteList.extensions == ["*", "abc"])
        #expect(filter.whiteList.names.contains("README"))
        #expect(filter.blackList.extensions.contains("mp3"))
        #expect(filter.blackList.names.contains(".SynologyUSBCopy.config"))
        #expect(restored.selectedExtensions.contains("mp3") == false)
        #expect(restored.customExtensions == ["abc"])
        #expect(restored.customNames == ["README"])
    }

    @Test func customFilterRulesAreAddedToTheOperationalAllowList() {
        var selection = USBCopyFilterSelection(
            selectedExtensions: [],
            includesOtherFiles: false,
            customExtensions: ["rtf"],
            customNames: ["LICENSE"]
        )

        let filter = selection.filter

        #expect(filter.whiteList.extensions == ["rtf"])
        #expect(filter.whiteList.names == ["LICENSE"])
        #expect(filter.customizedList.extensions == ["rtf"])
        #expect(filter.customizedList.names == ["LICENSE"])

        selection = USBCopyFilterSelection(filter: filter)
        #expect(selection.customExtensions == ["rtf"])
        #expect(selection.customNames == ["LICENSE"])
        #expect(selection.filter == filter)
    }

    @Test func onlyDefaultTasksExposeTheEnableAndDisableActions() throws {
        let disabled = try JSONDecoder().decode(
            USBCopyTask.self,
            from: Data(
                #"{"id":4,"name":"Default","type":"export_general","source_path":"/Files","destination_path":"[USB]","copy_strategy":"mirror","status":"disabled","is_default_task":true}"#.utf8
            )
        )
        let enabled = try JSONDecoder().decode(
            USBCopyTask.self,
            from: Data(
                #"{"id":5,"name":"Default","type":"export_general","source_path":"/Files","destination_path":"[USB]","copy_strategy":"mirror","status":"successful","is_default_task":true}"#.utf8
            )
        )
        let canceling = try JSONDecoder().decode(
            USBCopyTask.self,
            from: Data(
                #"{"id":6,"name":"Default","type":"export_general","source_path":"/Files","destination_path":"[USB]","copy_strategy":"mirror","status":"canceling","is_default_task":true}"#.utf8
            )
        )
        let unavailable = try JSONDecoder().decode(
            USBCopyTask.self,
            from: Data(
                #"{"id":7,"name":"Pending","type":"export_general","source_path":"/Files","destination_path":"[USB]","copy_strategy":"mirror","status":"na","is_default_task":false}"#.utf8
            )
        )

        #expect(disabled.canEnable)
        #expect(!disabled.canDisable)
        #expect(enabled.canDisable)
        #expect(!enabled.canEnable)
        #expect(!canceling.canDisable)
        #expect(!unavailable.canRun)
        #expect(!unavailable.canDelete)
    }

    @Test func filterSelectionPreservesRulesTheEditorDoesNotManage() {
        let original = USBCopyFilter(
            whiteList: USBCopyFileRules(extensions: ["mp3", "special"], names: ["Cover"]),
            blackList: USBCopyFileRules(
                extensions: ["legacy"],
                names: [".SynologyUSBCopy.config", "Temporary"]
            ),
            customizedList: USBCopyFileRules(extensions: ["custom"], names: ["README"])
        )

        var selection = USBCopyFilterSelection(filter: original)
        selection.selectedExtensions.insert("wav")
        let updated = selection.filter

        #expect(updated.whiteList.extensions.contains("special"))
        #expect(updated.whiteList.extensions.contains("wav"))
        #expect(updated.whiteList.names.contains("Cover"))
        #expect(updated.blackList.extensions.contains("legacy"))
        #expect(updated.blackList.names.contains("Temporary"))
        #expect(updated.blackList.names.contains(".SynologyUSBCopy.config"))
        #expect(updated.customizedList == original.customizedList)
    }

    @Test func validatesScheduledDaysAndReferenceDates() {
        var schedule = USBCopyScheduleContent.defaultValue

        #expect(schedule.hasSelectedWeekday)
        #expect(schedule.hasValidReferenceDate)

        schedule.weekDay = ""
        schedule.date = "2026/02/31"

        #expect(!schedule.hasSelectedWeekday)
        #expect(!schedule.hasValidReferenceDate)
    }

    private func makeService(stub: DSMRequestStub) -> DSMUSBCopyService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.USBCopy": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Core.TaskScheduler": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 4,
                requestFormat: "JSON"
            ),
            "SYNO.Core.Share": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Core.Storage.Volume": APIInfoEntry(
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
        return DSMUSBCopyService(transport: transport)
    }

    private func query(from request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}

private extension String {
    var jsonDictionary: [String: Any] {
        get throws {
            let object = try JSONSerialization.jsonObject(with: Data(utf8))
            return try #require(object as? [String: Any])
        }
    }
}
