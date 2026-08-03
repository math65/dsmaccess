//
//  HyperBackupTask.swift
//  dsmaccess
//
//  Backup tasks returned by SYNO.Backup.Task, and the progress block DSM only sends
//  while a backup is running.
//

import Foundation

/// Task states observed on DSM 7.4. An unknown value keeps its raw form rather than being
/// folded into a neighbouring case: the table then shows what DSM actually said.
enum HyperBackupTaskStatus: String, Sendable {
    case idle = "none"
    case backingUp = "backup"
    case cancelling = "canceling"

    var localizedName: String {
        switch self {
        case .idle: String(localized: "hyper_backup.task.status.idle")
        case .backingUp: String(localized: "hyper_backup.task.status.backing_up")
        case .cancelling: String(localized: "hyper_backup.task.status.cancelling")
        }
    }
}

/// The stages DSM reports through `progress.step`, in the order they were observed during a
/// complete backup. `title_type` duplicates the information more coarsely and is not used.
enum HyperBackupStep: String, Sendable {
    case preBackup = "prebackup"
    case preparing = "backup_prepare"
    case applications = "app_backup"
    case data = "data_backup"
    case configuration = "config_backup"
    case finishing = "backup_complete"

    var localizedName: String {
        switch self {
        case .preBackup: String(localized: "hyper_backup.step.pre_backup")
        case .preparing: String(localized: "hyper_backup.step.preparing")
        case .applications: String(localized: "hyper_backup.step.applications")
        case .data: String(localized: "hyper_backup.step.data")
        case .configuration: String(localized: "hyper_backup.step.configuration")
        case .finishing: String(localized: "hyper_backup.step.finishing")
        }
    }
}

/// Sizes and counters arrive as strings in this API, which is why they go through the
/// flexible decoders rather than plain `Int`.
struct HyperBackupProgress: nonisolated Decodable, Equatable, Sendable {
    let step: String
    let percentage: Int
    let showsPercentage: Bool
    let canCancel: Bool
    let canSuspend: Bool
    let averageSpeed: Int64
    let totalSize: Int64
    let processedSize: Int64
    let transmittedSize: Int64
    let scannedFileCount: Int64
    let countedFileCount: Int64
    let currentApplication: String?

    private enum CodingKeys: String, CodingKey {
        case step, progress
        case showsPercentage = "show_progress"
        case canCancel = "can_cancel"
        case canSuspend = "can_suspend"
        case averageSpeed = "avg_speed"
        case totalSize = "total_size"
        case processedSize = "processed_size"
        case transmittedSize = "transmitted_size"
        case scannedFileCount = "scan_file_count"
        case countedFileCount = "counted_file_count"
        case currentApplication = "current_app"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        step = values.flexString(.step) ?? ""
        percentage = values.flexInt(.progress) ?? 0
        showsPercentage = values.flexBool(.showsPercentage) ?? false
        canCancel = values.flexBool(.canCancel) ?? false
        canSuspend = values.flexBool(.canSuspend) ?? false
        averageSpeed = values.flexInt64(.averageSpeed) ?? 0
        totalSize = values.flexInt64(.totalSize) ?? 0
        processedSize = values.flexInt64(.processedSize) ?? 0
        transmittedSize = values.flexInt64(.transmittedSize) ?? 0
        scannedFileCount = values.flexInt64(.scannedFileCount) ?? 0
        countedFileCount = values.flexInt64(.countedFileCount) ?? 0
        let application = values.flexString(.currentApplication)
        currentApplication = (application?.isEmpty ?? true) ? nil : application
    }

    var knownStep: HyperBackupStep? { HyperBackupStep(rawValue: step) }

    /// Falls back to the raw DSM stage so an unrecognised step is still spoken and shown.
    var stepDescription: String { knownStep?.localizedName ?? step }
}

/// The lightweight triple returned by `SYNO.Backup.Task` `status`, plus the progress block
/// that only exists while the task runs.
struct HyperBackupTaskState: nonisolated Decodable, Equatable, Sendable {
    let taskID: Int
    let state: String
    let status: String
    let progress: HyperBackupProgress?

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case state, status, progress
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try values.requiredFlexInt(.taskID)
        state = try values.requiredFlexString(.state)
        status = try values.requiredFlexString(.status)
        progress = try values.decodeIfPresent(HyperBackupProgress.self, forKey: .progress)
    }

    var knownStatus: HyperBackupTaskStatus? { HyperBackupTaskStatus(rawValue: status) }
}

struct HyperBackupTask: nonisolated Decodable, Equatable, Identifiable, Sendable {
    let taskID: Int
    let name: String
    let repositoryID: Int
    let targetID: String
    let targetType: String
    let transferType: String
    let type: String
    let state: String
    let status: String
    let dataType: String?
    let isEncrypted: Bool

    /// Filled in from `SYNO.Backup.Task` `status`; absent until the task list has been refreshed
    /// with a live status.
    var liveState: HyperBackupTaskState?

    var id: Int { taskID }

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case name, type, state, status
        case repositoryID = "repo_id"
        case targetID = "target_id"
        case targetType = "target_type"
        case transferType = "transfer_type"
        case dataType = "data_type"
        case isEncrypted = "data_enc"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try values.requiredFlexInt(.taskID)
        name = try values.requiredFlexString(.name)
        repositoryID = values.flexInt(.repositoryID) ?? -1
        targetID = values.flexString(.targetID) ?? ""
        targetType = values.flexString(.targetType) ?? ""
        transferType = values.flexString(.transferType) ?? ""
        type = values.flexString(.type) ?? ""
        state = try values.requiredFlexString(.state)
        status = try values.requiredFlexString(.status)
        dataType = values.flexString(.dataType)
        isEncrypted = values.flexBool(.isEncrypted) ?? false
    }

    /// The status carried by the live poll wins over the one captured when the list was built.
    var effectiveStatus: String { liveState?.status ?? status }
    var effectiveState: String { liveState?.state ?? state }
    var progress: HyperBackupProgress? { liveState?.progress }

    var knownStatus: HyperBackupTaskStatus? { HyperBackupTaskStatus(rawValue: effectiveStatus) }
    var statusDescription: String { knownStatus?.localizedName ?? effectiveStatus }

    /// `type` reads `image:image_local` or `cloud_image:webdav`; the destination half is the
    /// part users recognise.
    var destinationDescription: String {
        let destination = transferType.isEmpty ? targetType : transferType
        return HyperBackupDestination.localizedName(for: destination)
    }

    var encryptionDescription: String {
        isEncrypted
            ? String(localized: "hyper_backup.task.encryption.encrypted")
            : String(localized: "hyper_backup.task.encryption.plain")
    }

    var isRunning: Bool { knownStatus == .backingUp || knownStatus == .cancelling }

    /// DSM answers with `can_cancel` while a backup runs; outside a run there is nothing to
    /// cancel. Never inferred from the status alone.
    var canCancel: Bool { progress?.canCancel ?? false }

    var canBackUp: Bool { !isRunning }

    var sortableStatus: String { statusDescription }
    var sortableDestination: String { destinationDescription }
    var sortableEncryption: String { encryptionDescription }
}

/// Known transfer types, named the way DSM names them in its own interface. An unmeasured
/// destination falls back to the raw DSM token instead of being mislabelled.
enum HyperBackupDestination {
    static func localizedName(for transferType: String) -> String {
        switch transferType {
        case "image_local", "local": String(localized: "hyper_backup.destination.local_folder")
        case "webdav": String(localized: "hyper_backup.destination.webdav")
        case "rsync", "rsync_ds": String(localized: "hyper_backup.destination.rsync")
        case "image_remote": String(localized: "hyper_backup.destination.remote_nas")
        default: transferType
        }
    }
}

struct HyperBackupTaskList: nonisolated Decodable, Sendable {
    let tasks: [HyperBackupTask]
    let isRestoring: Bool

    private enum CodingKeys: String, CodingKey {
        case tasks = "task_list"
        case isRestoring = "is_restoring"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try values.decodeIfPresent([HyperBackupTask].self, forKey: .tasks) ?? []
        isRestoring = values.flexBool(.isRestoring) ?? false
    }
}
