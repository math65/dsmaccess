//
//  USBCopyTask.swift
//  dsmaccess
//
//  Tâches renvoyées par l’API privée SYNO.USBCopy.
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
        case .importGeneral: String(localized: "Importer des données depuis un périphérique USB")
        case .exportGeneral: String(localized: "Exporter des données vers un périphérique USB")
        case .importPhoto: String(localized: "Importer des photos et vidéos")
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
        case .versioning: String(localized: "Versions multiples")
        case .mirror: String(localized: "Miroir")
        case .incremental: String(localized: "Copie incrémentielle")
        }
    }
}

enum USBCopyConflictPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case rename
    case overwrite

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .rename: String(localized: "Renommer le nouveau fichier")
        case .overwrite: String(localized: "Remplacer le fichier existant")
        }
    }
}

enum USBCopyRotationPolicy: String, CaseIterable, Codable, Identifiable, Sendable {
    case oldestVersion = "oldest_version"
    case smartRecycle = "smart_recycle"

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .oldestVersion: String(localized: "Supprimer les versions les plus anciennes")
        case .smartRecycle: String(localized: "Recyclage intelligent")
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
        case .initial: String(localized: "Jamais exécutée")
        case .successful: String(localized: "Terminée")
        case .failed: String(localized: "Échec")
        case .waiting: String(localized: "En attente")
        case .copying: String(localized: "Copie en cours")
        case .disabled: String(localized: "Désactivée")
        case .unmounted: String(localized: "Périphérique déconnecté")
        case .shareUnavailable: String(localized: "Dossier indisponible")
        case .shareDeleted: String(localized: "Dossier supprimé")
        case .canceling: String(localized: "Annulation en cours")
        case .notAvailable: String(localized: "Non disponible")
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
