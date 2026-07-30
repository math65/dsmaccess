//
//  USBCopyTask.swift
//  dsmaccess
//
//  Tasks returned by the private SYNO.USBCopy API.
//

import Foundation

enum USBCopyTaskType: String, CaseIterable, Codable, Identifiable, Sendable {
    case importGeneral = "import_general"
    case exportGeneral = "export_general"
    case importPhoto = "import_photo"

    var id: Self { self }

    var isImport: Bool { self != .exportGeneral }

    var localizedName: String {
        switch self {
        case .importGeneral: String(localized: "usb_copy.task.mode.import")
        case .exportGeneral: String(localized: "usb_copy.task.mode.export")
        case .importPhoto: String(localized: "usb_copy.task.mode.import_photos")
        }
    }
}

enum USBCopyStrategy: String, CaseIterable, Codable, Identifiable, Sendable {
    case versioning
    case mirror
    case incremental

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .versioning: String(localized: "usb_copy.task.copy_mode.multi_version")
        case .mirror: String(localized: "usb_copy.task.copy_mode.mirror")
        case .incremental: String(localized: "common.label.incremental_copy")
        }
    }
}

enum USBCopyConflictPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case rename
    case overwrite

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .rename: String(localized: "usb_copy.task.conflict.rename")
        case .overwrite: String(localized: "usb_copy.task.conflict.overwrite")
        }
    }
}

enum USBCopyRotationPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case oldestVersion = "oldest_version"
    case smartRecycle = "smart_recycle"

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .oldestVersion: String(localized: "usb_copy.task.rotation.delete_oldest")
        case .smartRecycle: String(localized: "usb_copy.task.rotation.smart_recycle")
        }
    }
}

enum USBCopyTaskStatus: String, Sendable {
    case initial
    case successful
    case failed
    case waiting
    case copying
    case disabled
    case unmounted
    case shareUnavailable
    case shareDeleted
    case canceling
    case notAvailable = "na"

    var localizedName: String {
        switch self {
        case .initial: String(localized: "usb_copy.task.status.never_run")
        case .successful: String(localized: "common.status.completed.feminine")
        case .failed: String(localized: "common.status.failed")
        case .waiting: String(localized: "common.status.waiting")
        case .copying: String(localized: "usb_copy.task.status.copying")
        case .disabled: String(localized: "common.status.disabled.feminine")
        case .unmounted: String(localized: "usb_copy.task.status.device_disconnected")
        case .shareUnavailable: String(localized: "usb_copy.task.status.folder_unavailable")
        case .shareDeleted: String(localized: "usb_copy.task.status.folder_deleted")
        case .canceling: String(localized: "usb_copy.task.status.cancelling")
        case .notAvailable: String(localized: "common.value.not_available")
        }
    }
}

struct USBCopyTask: nonisolated Decodable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let type: String
    let sourcePath: String
    let destinationPath: String
    let copyStrategy: String
    let conflictPolicy: String?
    let scheduleID: Int?
    let removeSourceFile: Bool?
    let ejectWhenTaskDone: Bool?
    let runWhenPlugIn: Bool?
    let notKeepDirectoryStructure: Bool?
    let maxVersionCount: Int?
    let enableRotation: Bool?
    let rotationPolicy: String?
    let smartCreateDateDirectory: Bool?
    let renamePhotoVideo: Bool?
    let isUSBMounted: Bool?
    let isDSMounted: Bool?
    let isTaskRunnable: Bool?
    let isDefaultTask: Bool?
    let status: String
    let errorCode: Int?
    let latestFinishTime: Int?
    let nextRunTime: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, type, status
        case sourcePath = "source_path"
        case destinationPath = "destination_path"
        case copyStrategy = "copy_strategy"
        case conflictPolicy = "conflict_policy"
        case scheduleID = "schedule_id"
        case removeSourceFile = "remove_src_file"
        case ejectWhenTaskDone = "eject_when_task_done"
        case runWhenPlugIn = "run_when_plug_in"
        case notKeepDirectoryStructure = "not_keep_dir_structure"
        case maxVersionCount = "max_version_count"
        case enableRotation = "enable_rotation"
        case rotationPolicy = "rotation_policy"
        case smartCreateDateDirectory = "smart_create_date_dir"
        case renamePhotoVideo = "rename_photo_video"
        case isUSBMounted = "is_usb_mounted"
        case isDSMounted = "is_ds_mounted"
        case isTaskRunnable = "is_task_runnable"
        case isDefaultTask = "is_default_task"
        case errorCode = "error_code"
        case latestFinishTime = "latest_finish_time"
        case nextRunTime = "next_run_time"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.requiredFlexInt(.id)
        name = try values.requiredFlexString(.name)
        type = try values.requiredFlexString(.type)
        sourcePath = try values.requiredFlexString(.sourcePath)
        destinationPath = try values.requiredFlexString(.destinationPath)
        copyStrategy = try values.requiredFlexString(.copyStrategy)
        status = try values.requiredFlexString(.status)
        conflictPolicy = values.flexString(.conflictPolicy)
        scheduleID = values.flexInt(.scheduleID)
        removeSourceFile = values.flexBool(.removeSourceFile)
        ejectWhenTaskDone = values.flexBool(.ejectWhenTaskDone)
        runWhenPlugIn = values.flexBool(.runWhenPlugIn)
        notKeepDirectoryStructure = values.flexBool(.notKeepDirectoryStructure)
        maxVersionCount = values.flexInt(.maxVersionCount)
        enableRotation = values.flexBool(.enableRotation)
        rotationPolicy = values.flexString(.rotationPolicy)
        smartCreateDateDirectory = values.flexBool(.smartCreateDateDirectory)
        renamePhotoVideo = values.flexBool(.renamePhotoVideo)
        isUSBMounted = values.flexBool(.isUSBMounted)
        isDSMounted = values.flexBool(.isDSMounted)
        isTaskRunnable = values.flexBool(.isTaskRunnable)
        isDefaultTask = values.flexBool(.isDefaultTask)
        errorCode = values.flexInt(.errorCode)
        latestFinishTime = values.flexInt(.latestFinishTime)
        nextRunTime = values.flexString(.nextRunTime)
    }

    var knownType: USBCopyTaskType? { USBCopyTaskType(rawValue: type) }
    var knownStrategy: USBCopyStrategy? { USBCopyStrategy(rawValue: copyStrategy) }
    var knownStatus: USBCopyTaskStatus? { USBCopyTaskStatus(rawValue: status) }
    var isActive: Bool { knownStatus == .waiting || knownStatus == .copying || knownStatus == .canceling }
    var canCancel: Bool { knownStatus == .waiting || knownStatus == .copying }
    var canRun: Bool {
        knownStatus == .initial || knownStatus == .successful
            || (knownStatus == .failed && isTaskRunnable == true)
    }
    var canEnable: Bool { knownStatus == .disabled }
    var canDisable: Bool {
        isDefaultTask == true && knownStatus != nil && knownStatus != .disabled
            && knownStatus != .canceling && knownStatus != .notAvailable
    }
    var canToggleEnabled: Bool { canEnable || canDisable }
    var canDelete: Bool {
        isDefaultTask == false && knownStatus != .canceling && knownStatus != .notAvailable
    }
}

struct USBCopyTaskList: nonisolated Decodable, Sendable {
    let tasks: [USBCopyTask]
}

struct USBCopyTaskResult: nonisolated Decodable, Sendable {
    let task: USBCopyTask
}

struct USBCopyTaskCreationResult: nonisolated Decodable, Sendable {
    let taskID: Int

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
    }
}
