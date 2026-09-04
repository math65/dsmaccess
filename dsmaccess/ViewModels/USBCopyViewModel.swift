//
//  USBCopyViewModel.swift
//  dsmaccess
//
//  State and orchestration of USB Copy operations.
//

import Foundation
import Observation

@MainActor
@Observable
final class USBCopyViewModel {
    private(set) var tasks: [USBCopyTask] = []
    private(set) var availableShares: [SharedFolder] = []
    private(set) var isLoading = false
    private(set) var busyTaskIDs: Set<Int> = []
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if !silently { isLoading = true }
        errorMessage = nil
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            let result = try await session.withClient { client in
                let tasks = try await client.listUSBCopyTasks().sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                let shares = try await client.usbCopyAvailableShares()
                return (tasks, shares)
            }
            guard generation == loadGeneration else { return }
            tasks = result.0
            availableShares = result.1
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = reason(for: error)
        }
    }

    func details(taskID: Int) async throws -> USBCopyTaskDetails {
        try await session.withClient { client in
            let task = try await client.usbCopyTask(id: taskID)
            async let filter = client.usbCopyFilter(taskID: taskID)
            async let trigger = client.usbCopyTrigger(for: task)
            let (loadedFilter, loadedTrigger) = try await (filter, trigger)
            return USBCopyTaskDetails(
                task: task,
                filter: loadedFilter,
                trigger: loadedTrigger
            )
        }
    }

    func create(_ task: USBCopyTaskCreation) async -> DSMOperationOutcome {
        do {
            _ = try await session.withClient { try await $0.createUSBCopyTask(task) }
            await load()
            return .success(String(localized: "usb_copy.announcement.task_created", defaultValue: "USB Copy task created: \(task.name)"))
        } catch {
            return failure(error, action: String(localized: "usb_copy.operation.create"))
        }
    }

    func save(_ settings: USBCopyTaskSettings) async -> DSMOperationOutcome {
        let enablesDefaultTask = tasks.first(where: { $0.id == settings.id }).map {
            $0.isDefaultTask == true && $0.canEnable
                && $0.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        let saveOutcome = await perform(taskID: settings.id, action: String(localized: "usb_copy.operation.task_update")) {
            try await $0.setUSBCopyTaskSettings(settings)
            return String(localized: "usb_copy.announcement.task_updated", defaultValue: "USB Copy task updated: \(settings.name)")
        }
        guard enablesDefaultTask, case .success = saveOutcome,
              let task = tasks.first(where: { $0.id == settings.id }) else {
            return saveOutcome
        }

        let enableOutcome = await enable(task)
        return switch enableOutcome {
        case .success:
            .success(String(localized: "usb_copy.announcement.task_saved_enabled", defaultValue: "Task saved and enabled: \(settings.name)"))
        case .failure(let message):
            .failure(String(localized: "usb_copy.error.enable_failed", defaultValue: "The folder was saved, but the task could not be enabled. \(message)"))
        case .cancelled:
            .failure(String(localized: "usb_copy.error.enable_cancelled"))
        }
    }

    func save(_ trigger: USBCopyTrigger, task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "usb_copy.operation.trigger_update")) {
            try await $0.setUSBCopyTrigger(trigger, taskID: task.id)
            return String(localized: "usb_copy.announcement.trigger_updated", defaultValue: "Trigger updated for \(task.name)")
        }
    }

    func save(_ filter: USBCopyFilter, task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "usb_copy.operation.filter_update")) {
            try await $0.setUSBCopyFilter(filter, taskID: task.id)
            return String(localized: "usb_copy.announcement.filter_updated", defaultValue: "Filter updated for \(task.name)")
        }
    }

    func run(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "usb_copy.operation.start")) {
            try await $0.runUSBCopyTask(id: task.id)
            return String(localized: "common.status.task_started", defaultValue: "Task started: \(task.name)")
        }
    }

    func cancel(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "usb_copy.operation.cancel")) {
            try await $0.cancelUSBCopyTask(id: task.id)
            return String(localized: "usb_copy.announcement.cancel_requested", defaultValue: "Cancellation requested: \(task.name)")
        }
    }

    func enable(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "usb_copy.operation.enable")) {
            try await $0.enableUSBCopyTask(id: task.id)
            return String(localized: "common.status.task_enabled", defaultValue: "Task enabled: \(task.name)")
        }
    }

    func disable(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "usb_copy.operation.disable")) {
            try await $0.disableUSBCopyTask(id: task.id)
            return String(localized: "common.status.task_disabled", defaultValue: "Task disabled: \(task.name)")
        }
    }

    func delete(_ task: USBCopyTask) async -> DSMOperationOutcome {
        await perform(taskID: task.id, action: String(localized: "usb_copy.operation.delete")) {
            try await $0.deleteUSBCopyTask(id: task.id)
            return String(localized: "common.status.task_deleted", defaultValue: "Task deleted: \(task.name)")
        }
    }

    func globalSettings() async throws -> USBCopyGlobalSettings {
        try await session.withClient { try await $0.usbCopyGlobalSettings() }
    }

    func repositoryVolumePaths() async throws -> [String] {
        try await session.withClient { try await $0.usbCopyAvailableVolumePaths() }
    }

    func folders(in path: String) async throws -> [FileStationItem] {
        try await session.withClient { client in
            try await client.list(folderPath: path)
                .filter(\.isdir)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func saveGlobalSettings(_ settings: USBCopyGlobalSettings) async -> DSMOperationOutcome {
        guard (5...100_000).contains(settings.logRotateCount) else {
            return .failure(String(localized: "usb_copy.error.log_count_range"))
        }
        do {
            try await session.withClient { try await $0.setUSBCopyGlobalSettings(settings) }
            return .success(String(localized: "usb_copy.announcement.global_settings_saved"))
        } catch {
            return failure(error, action: String(localized: "usb_copy.operation.save_global_settings"))
        }
    }

    func logs(
        filter: USBCopyLogFilter,
        offset: Int = 0,
        limit: Int = 200
    ) async throws -> USBCopyLogPage {
        try await session.withClient {
            try await $0.usbCopyLogs(offset: offset, limit: limit, filter: filter)
        }
    }

    var localShares: [SharedFolder] {
        availableShares.filter {
            $0.externalDeviceType != "USB" && $0.externalDeviceType != "SDCARD"
        }
    }

    var externalShares: [SharedFolder] {
        availableShares.filter {
            $0.externalDeviceType == "USB" || $0.externalDeviceType == "SDCARD"
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let activeCount = tasks.count(where: \.isActive)
        return String(localized: "usb_copy.list.summary", defaultValue: "\(tasks.count) USB Copy tasks, \(activeCount) active")
    }

    private func perform(
        taskID: Int,
        action: String,
        operation: (DSMClientProtocol) async throws -> String
    ) async -> DSMOperationOutcome {
        guard !busyTaskIDs.contains(taskID) else { return .cancelled }
        busyTaskIDs.insert(taskID)
        defer { busyTaskIDs.remove(taskID) }
        do {
            let message = try await session.withClient(operation)
            await load(silently: true)
            return .success(message)
        } catch {
            await load(silently: true)
            return failure(error, action: action)
        }
    }

    private func failure(_ error: Error, action: String) -> DSMOperationOutcome {
        guard !DSMError.isCancellation(error) else { return .cancelled }
        return .failure(String(localized: "usb_copy.error.operation_failed", defaultValue: "Failed while \(action): \(reason(for: error))"))
    }

    private func reason(for error: Error) -> String {
        if case let DSMError.apiError(code, _) = error {
            switch code {
            case 401: return String(localized: "usb_copy.error.internal")
            case 402: return String(localized: "usb_copy.error.invalid_setting")
            case 403: return String(localized: "usb_copy.error.device_in_use")
            case 404: return String(localized: "usb_copy.error.repository_missing")
            case 405: return String(localized: "usb_copy.error.initializing")
            case 406: return String(localized: "usb_copy.error.upgrading")
            case 407: return String(localized: "usb_copy.error.repository_moving")
            case 408: return String(localized: "usb_copy.error.volume_invalid")
            case 409: return String(localized: "usb_copy.error.volume_no_space")
            case 410: return String(localized: "usb_copy.error.destination_in_use")
            case 411: return String(localized: "usb_copy.error.unknown_device")
            case 413: return String(localized: "usb_copy.error.destination_missing")
            case 414: return String(localized: "usb_copy.error.invalid_path")
            case 415: return String(localized: "usb_copy.error.upgrade_failed")
            case 416: return String(localized: "usb_copy.error.shared_folder_missing")
            case 417: return String(localized: "usb_copy.error.shared_folder_not_mounted")
            case 418: return String(localized: "usb_copy.error.shared_folder_unavailable")
            case 419: return String(localized: "usb_copy.error.source_missing")
            case 420: return String(localized: "usb_copy.error.volume_locked")
            default: break
            }
        }
        return (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}

struct USBCopyTaskDetails: Sendable {
    let task: USBCopyTask
    let filter: USBCopyFilter
    let trigger: USBCopyTrigger
}
