//
//  DSMUSBCopyService.swift
//  dsmaccess
//
//  Gestion de USB Copy via les contrats observés dans le client DSM officiel.
//

import Foundation

@MainActor
final class DSMUSBCopyService {
    private static let usbCopyAPI = DSMAPI("SYNO.USBCopy")
    private static let taskSchedulerAPI = DSMAPI("SYNO.Core.TaskScheduler", preferredVersion: 2)
    private static let shareAPI = DSMAPI("SYNO.Core.Share", preferredVersion: 1)
    private static let volumeAPI = DSMAPI("SYNO.Core.Storage.Volume", preferredVersion: 1)

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func tasks() async throws -> [USBCopyTask] {
        try await transport.read(
            api: Self.usbCopyAPI,
            method: "list",
            as: USBCopyTaskList.self
        ).tasks
    }

    func task(id: Int) async throws -> USBCopyTask {
        try await transport.read(
            api: Self.usbCopyAPI,
            method: "get",
            parameters: ["id": .integer(id)],
            as: USBCopyTaskResult.self
        ).task
    }

    func create(_ task: USBCopyTaskCreation) async throws -> Int {
        let normalizedTask = task.normalizedForAPI
        return try await transport.value(
            api: Self.usbCopyAPI,
            method: "create",
            parameters: ["task": try DSMParameter.json(normalizedTask)],
            as: USBCopyTaskCreationResult.self
        ).taskID
    }

    func setSettings(_ settings: USBCopyTaskSettings) async throws {
        let normalizedSettings = settings.normalizedForAPI
        try await transport.perform(
            api: Self.usbCopyAPI,
            method: "set_setting",
            parameters: [
                "id": .integer(settings.id),
                "task_setting": try DSMParameter.json(normalizedSettings),
            ]
        )
    }

    func filter(taskID: Int) async throws -> USBCopyFilter {
        try await transport.read(
            api: Self.usbCopyAPI,
            method: "get_filter",
            parameters: ["id": .integer(taskID)],
            as: USBCopyFilterResult.self
        ).taskFilter
    }

    func setFilter(_ filter: USBCopyFilter, taskID: Int) async throws {
        try await transport.perform(
            api: Self.usbCopyAPI,
            method: "set_filter",
            parameters: [
                "id": .integer(taskID),
                "task_filter": try DSMParameter.json(filter),
            ]
        )
    }

    func trigger(for task: USBCopyTask) async throws -> USBCopyTrigger {
        guard let scheduleID = task.scheduleID, scheduleID != -1 else {
            return USBCopyTrigger(
                runWhenPlugIn: task.runWhenPlugIn ?? false,
                ejectWhenTaskDone: task.ejectWhenTaskDone ?? true,
                scheduleEnabled: false,
                scheduleContent: .defaultValue
            )
        }
        let scheduler = try await transport.read(
            api: Self.taskSchedulerAPI,
            method: "get",
            parameters: ["id": .integer(scheduleID)],
            as: USBCopySchedulerResult.self
        )
        return USBCopyTrigger(
            runWhenPlugIn: task.runWhenPlugIn ?? false,
            ejectWhenTaskDone: task.ejectWhenTaskDone ?? true,
            scheduleEnabled: scheduler.enable,
            scheduleContent: scheduler.schedule
        )
    }

    func setTrigger(_ trigger: USBCopyTrigger, taskID: Int) async throws -> USBCopyTriggerResult {
        try await transport.value(
            api: Self.usbCopyAPI,
            method: "set_trigger_time",
            parameters: [
                "id": .integer(taskID),
                "trigger_time": try DSMParameter.json(trigger),
            ],
            as: USBCopyTriggerResult.self
        )
    }

    func globalSettings() async throws -> USBCopyGlobalSettings {
        try await transport.read(
            api: Self.usbCopyAPI,
            method: "get_global_setting",
            as: USBCopyGlobalSettings.self
        )
    }

    func setGlobalSettings(_ settings: USBCopyGlobalSettings) async throws {
        try await transport.perform(
            api: Self.usbCopyAPI,
            method: "set_global_setting",
            parameters: [
                "repo_volume_path": .string(settings.repositoryVolumePath),
                "log_rotate_count": .integer(settings.logRotateCount),
                "beep_on_task_start_end": .boolean(settings.beepOnTaskStartEnd),
            ]
        )
    }

    func logs(
        offset: Int,
        limit: Int,
        filter: USBCopyLogFilter
    ) async throws -> USBCopyLogPage {
        try await transport.read(
            api: Self.usbCopyAPI,
            method: "get_log_list",
            parameters: [
                "offset": .integer(offset),
                "limit": .integer(limit),
                "log_filter": try DSMParameter.json(filter),
            ],
            as: USBCopyLogPage.self
        )
    }

    func availableShares() async throws -> [SharedFolder] {
        let result = try await transport.read(
            api: Self.shareAPI,
            method: "list",
            parameters: [
                "shareType": try DSMParameter.json(["local", "usb", "dec", "c2"]),
            ],
            as: ShareList.self
        )
        return result.shares ?? []
    }

    func availableVolumePaths() async throws -> [String] {
        let result = try await transport.read(
            api: Self.volumeAPI,
            method: "list",
            parameters: [
                "limit": .integer(-1),
                "offset": .integer(0),
                "location": .string("internal"),
            ],
            as: USBCopyVolumeList.self
        )
        return result.volumes
            .filter { ($0.sizeTotalByte ?? 0) > 0 }
            .map(\.volumePath)
    }

    func run(taskID: Int) async throws {
        try await action("run", taskID: taskID)
    }

    func cancel(taskID: Int) async throws {
        try await action("cancel", taskID: taskID)
    }

    func enable(taskID: Int) async throws {
        try await action("enable", taskID: taskID)
    }

    func disable(taskID: Int) async throws {
        try await action("disable", taskID: taskID)
    }

    func delete(taskID: Int) async throws {
        try await action("delete", taskID: taskID)
    }

    private func action(_ method: String, taskID: Int) async throws {
        try await transport.perform(
            api: Self.usbCopyAPI,
            method: method,
            parameters: ["id": .integer(taskID)]
        )
    }
}

private struct USBCopyVolumeList: nonisolated Decodable, Sendable {
    let volumes: [USBCopyVolume]
}

private struct USBCopyVolume: nonisolated Decodable, Sendable {
    let volumePath: String
    let sizeTotalByte: Int64?

    private enum CodingKeys: String, CodingKey {
        case volumePath = "volume_path"
        case sizeTotalByte = "size_total_byte"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        volumePath = try values.requiredFlexString(.volumePath)
        sizeTotalByte = values.flexInt64(.sizeTotalByte)
    }
}
