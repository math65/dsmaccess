//
//  USBCopyConfiguration.swift
//  dsmaccess
//
//  Réglages des tâches, déclencheurs et paramètres globaux de USB Copy.
//

import Foundation

struct USBCopyScheduleContent: nonisolated Codable, Equatable, Sendable {
    var dateType: Int
    var weekDay: String
    var date: String
    var repeatDate: Int
    var hour: Int
    var minute: Int
    var repeatHour: Int
    var lastWorkHour: Int

    enum CodingKeys: String, CodingKey {
        case date
        case dateType = "date_type"
        case weekDay = "week_day"
        case repeatDate = "repeat_date"
        case hour, minute
        case repeatHour = "repeat_hour"
        case lastWorkHour = "last_work_hour"
    }

    static var defaultValue: Self {
        let format = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)/\(month: .twoDigits)/\(day: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .current,
            calendar: Calendar(identifier: .gregorian)
        )
        return Self(
            dateType: 0,
            weekDay: "0,1,2,3,4,5,6",
            date: Date.now.formatted(format),
            repeatDate: 0,
            hour: 0,
            minute: 0,
            repeatHour: 0,
            lastWorkHour: 0
        )
    }

    var hasSelectedWeekday: Bool {
        weekDay.split(separator: ",").contains { Int($0) != nil }
    }

    var hasValidReferenceDate: Bool {
        let style = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)/\(month: .twoDigits)/\(day: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: .current,
            calendar: Calendar(identifier: .gregorian)
        )
        return (try? Date(date, strategy: style.parseStrategy)) != nil
    }
}

struct USBCopyTrigger: nonisolated Codable, Equatable, Sendable {
    var runWhenPlugIn: Bool
    var ejectWhenTaskDone: Bool
    var scheduleEnabled: Bool
    var scheduleContent: USBCopyScheduleContent

    enum CodingKeys: String, CodingKey {
        case runWhenPlugIn = "run_when_plug_in"
        case ejectWhenTaskDone = "eject_when_task_done"
        case scheduleEnabled = "schedule_enabled"
        case scheduleContent = "schedule_content"
    }
}

struct USBCopyTriggerResult: nonisolated Decodable, Sendable {
    let scheduleID: Int
    let nextRunTime: String?

    private enum CodingKeys: String, CodingKey {
        case scheduleID = "schedule_id"
        case nextRunTime = "next_run_time"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        scheduleID = try values.requiredFlexInt(.scheduleID)
        nextRunTime = values.flexString(.nextRunTime)
    }
}

struct USBCopySchedulerResult: nonisolated Decodable, Sendable {
    let enable: Bool
    let schedule: USBCopyScheduleContent

    private enum CodingKeys: String, CodingKey {
        case enable, schedule
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enable = values.flexBool(.enable) ?? false
        schedule = try values.decode(USBCopyScheduleContent.self, forKey: .schedule)
    }
}

struct USBCopyTaskSettings: nonisolated Encodable, Equatable, Sendable {
    var id: Int
    var type: USBCopyTaskType
    var name: String
    var sourcePath: String
    var destinationPath: String
    var copyStrategy: USBCopyStrategy
    var enableRotation: Bool
    var rotationPolicy: USBCopyRotationPolicy
    var maxVersionCount: Int
    var removeSourceFile: Bool
    var notKeepDirectoryStructure: Bool
    var smartCreateDateDirectory: Bool
    var renamePhotoVideo: Bool
    var conflictPolicy: USBCopyConflictPolicy

    enum CodingKeys: String, CodingKey {
        case id, type, name
        case sourcePath = "source_path"
        case destinationPath = "destination_path"
        case copyStrategy = "copy_strategy"
        case enableRotation = "enable_rotation"
        case rotationPolicy = "rotation_policy"
        case maxVersionCount = "max_version_count"
        case removeSourceFile = "remove_src_file"
        case notKeepDirectoryStructure = "not_keep_dir_structure"
        case smartCreateDateDirectory = "smart_create_date_dir"
        case renamePhotoVideo = "rename_photo_video"
        case conflictPolicy = "conflict_policy"
    }

    var normalizedForAPI: Self {
        guard type == .importPhoto else { return self }
        var normalized = self
        normalized.copyStrategy = .incremental
        normalized.enableRotation = false
        normalized.notKeepDirectoryStructure = true
        normalized.smartCreateDateDirectory = true
        normalized.renamePhotoVideo = true
        normalized.conflictPolicy = .rename
        return normalized
    }
}

struct USBCopyTaskCreation: nonisolated Encodable, Equatable, Sendable {
    var type: USBCopyTaskType
    var name: String
    var sourcePath: String
    var destinationPath: String
    var copyStrategy: USBCopyStrategy
    var enableRotation: Bool?
    var rotationPolicy: USBCopyRotationPolicy?
    var maxVersionCount: Int?
    var removeSourceFile: Bool?
    var notKeepDirectoryStructure: Bool?
    var smartCreateDateDirectory: Bool?
    var renamePhotoVideo: Bool?
    var conflictPolicy: USBCopyConflictPolicy?
    var runWhenPlugIn: Bool
    var ejectWhenTaskDone: Bool
    var scheduleEnabled: Bool
    var scheduleContent: USBCopyScheduleContent
    var filter: USBCopyFilter

    enum CodingKeys: String, CodingKey {
        case type, name, filter
        case sourcePath = "source_path"
        case destinationPath = "destination_path"
        case copyStrategy = "copy_strategy"
        case enableRotation = "enable_rotation"
        case rotationPolicy = "rotation_policy"
        case maxVersionCount = "max_version_count"
        case removeSourceFile = "remove_src_file"
        case notKeepDirectoryStructure = "not_keep_dir_structure"
        case smartCreateDateDirectory = "smart_create_date_dir"
        case renamePhotoVideo = "rename_photo_video"
        case conflictPolicy = "conflict_policy"
        case runWhenPlugIn = "run_when_plug_in"
        case ejectWhenTaskDone = "eject_when_task_done"
        case scheduleEnabled = "schedule_enabled"
        case scheduleContent = "schedule_content"
    }

    var normalizedForAPI: Self {
        guard type == .importPhoto else { return self }
        var normalized = self
        normalized.copyStrategy = .incremental
        normalized.enableRotation = nil
        normalized.rotationPolicy = nil
        normalized.maxVersionCount = nil
        normalized.notKeepDirectoryStructure = true
        normalized.smartCreateDateDirectory = true
        normalized.renamePhotoVideo = true
        normalized.conflictPolicy = .rename
        normalized.scheduleEnabled = false
        return normalized
    }
}

struct USBCopyGlobalSettings: nonisolated Codable, Equatable, Sendable {
    var repositoryVolumePath: String
    var logRotateCount: Int
    var beepOnTaskStartEnd: Bool

    enum CodingKeys: String, CodingKey {
        case repositoryVolumePath = "repo_volume_path"
        case logRotateCount = "log_rotate_count"
        case beepOnTaskStartEnd = "beep_on_task_start_end"
    }
}
