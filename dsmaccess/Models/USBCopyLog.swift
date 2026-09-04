//
//  USBCopyLog.swift
//  dsmaccess
//
//  Journal de USB Copy.
//

import Foundation

enum USBCopyLogType: Int, CaseIterable, Identifiable, Sendable {
    case information = 1
    case error = 2
    case warning = 4
    case all = 7

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .information: String(localized: "common.label.information")
        case .error: String(localized: "common.level.errors")
        case .warning: String(localized: "common.level.warnings")
        case .all: String(localized: "usb_copy.log.filter.all_events")
        }
    }
}

struct USBCopyLogFilter: nonisolated Encodable, Equatable, Sendable {
    var descriptionIDs: [Int]
    var keyword: String?
    var fromTimestamp: Int?
    var toTimestamp: Int?
    var logType: Int?

    enum CodingKeys: String, CodingKey {
        case descriptionIDs = "log_desc_id_list"
        case keyword = "key_word"
        case fromTimestamp = "from_timestamp"
        case toTimestamp = "to_timestamp"
        case logType = "log_type"
    }

    static let all = Self(
        descriptionIDs: [0, 1, 2, 3, 10, 11, 100, 101, 102, 103, 104, 105, 1000],
        keyword: nil,
        fromTimestamp: nil,
        toTimestamp: nil,
        logType: USBCopyLogType.all.rawValue
    )
}

struct USBCopyLogEntry: nonisolated Decodable, Identifiable, Sendable {
    let descriptionID: Int
    let descriptionParameter: String?
    let error: String?
    let logType: Int
    let taskID: Int?
    let timestamp: Int

    enum CodingKeys: String, CodingKey {
        case error, timestamp
        case descriptionID = "description_id"
        case descriptionParameter = "description_parameter"
        case logType = "log_type"
        case taskID = "task_id"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        descriptionID = try values.requiredFlexInt(.descriptionID)
        descriptionParameter = values.flexString(.descriptionParameter)
        error = values.flexString(.error)
        logType = try values.requiredFlexInt(.logType)
        taskID = values.flexInt(.taskID)
        timestamp = try values.requiredFlexInt(.timestamp)
    }

    var id: String { "\(timestamp)-\(taskID ?? -1)-\(descriptionID)-\(descriptionParameter ?? "")" }

    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }

    var logTypeName: String {
        USBCopyLogType(rawValue: logType)?.localizedName
            ?? String(localized: "common.value.not_available")
    }

    var taskDescription: String {
        guard let taskID else { return "—" }
        return String(
            localized: "usb_copy.log.task.fallback_name",
            defaultValue: "Task \(taskID)"
        )
    }

    /// The readable texts live here rather than in the view because the table sorts on them:
    /// sorting the raw identifier would order the rows by a DSM number while the column shows
    /// the sentence.
    var eventDescription: String {
        let parameter = decodedParameter
        return switch descriptionID {
        case 0: String(localized: "usb_copy.log.event.task_created", defaultValue: "Task created: \(parameter)")
        case 1: String(localized: "common.status.task_deleted", defaultValue: "Task deleted: \(parameter)")
        case 2: String(localized: "common.status.task_enabled", defaultValue: "Task enabled: \(parameter)")
        case 3: String(localized: "common.status.task_disabled", defaultValue: "Task disabled: \(parameter)")
        case 10: String(localized: "usb_copy.log.event.task_renamed", defaultValue: "Task name changed: \(parameter)")
        case 11: String(localized: "usb_copy.log.event.task_settings_changed", defaultValue: "Task settings changed: \(parameter)")
        case 100: String(localized: "common.status.task_started", defaultValue: "Task started: \(parameter)")
        case 101: String(localized: "usb_copy.log.event.task_completed", defaultValue: "Task completed: \(parameter)")
        case 102: String(localized: "usb_copy.log.event.task_cancelled", defaultValue: "Task cancelled: \(parameter)")
        case 103: String(localized: "usb_copy.log.event.task_failed", defaultValue: "Task failed: \(parameter)")
        case 104: String(localized: "usb_copy.log.event.version_rotation", defaultValue: "Version rotation: \(parameter)")
        case 105: String(localized: "usb_copy.log.event.task_completed_with_errors", defaultValue: "Task completed with errors: \(parameter)")
        case 1000: String(localized: "usb_copy.log.event.file_error", defaultValue: "File error: \(parameter)")
        default: String(localized: "usb_copy.log.event.row.label", defaultValue: "USB Copy event \(descriptionID): \(parameter)")
        }
    }

    private var decodedParameter: String {
        guard let raw = descriptionParameter, !raw.isEmpty else {
            return String(localized: "usb_copy.log.reason.no_details")
        }
        guard let data = raw.data(using: .utf8) else { return raw }
        if let value = try? JSONDecoder().decode(String.self, from: data) { return value }
        if let values = try? JSONDecoder().decode([String].self, from: data) {
            return values.formatted(.list(type: .and))
        }
        return raw
    }

    var errorText: String? {
        guard let raw = error, !raw.isEmpty else { return nil }
        guard let code = Int(raw) else { return raw }
        guard code != 0 else { return nil }
        return switch code {
        case -1: String(localized: "usb_copy.log.reason.cancellation")
        case -4: String(localized: "usb_copy.log.reason.invalid_parameter")
        case -9: String(localized: "common.error.permission_denied")
        case -10: String(localized: "usb_copy.log.reason.file_error")
        case -11: String(localized: "usb_copy.log.reason.file_too_large")
        case -12: String(localized: "usb_copy.log.reason.unsupported_file_name")
        case -13: String(localized: "usb_copy.log.reason.folder_unmounted")
        case -14: String(localized: "usb_copy.log.reason.resume_failed")
        case -15: String(localized: "usb_copy.log.reason.source_file_missing")
        case -16: String(localized: "usb_copy.log.reason.destination_file_exists")
        case -17: String(localized: "usb_copy.log.reason.destination_conflict")
        case -18: String(localized: "usb_copy.log.reason.incompatible_destination_type")
        case -19: String(localized: "usb_copy.log.reason.destination_full")
        case -20: String(localized: "usb_copy.log.reason.destination_root_missing")
        case -21: String(localized: "usb_copy.log.reason.destination_parent_missing")
        case -22: String(localized: "usb_copy.log.reason.source_root_missing")
        case -24: String(localized: "usb_copy.log.reason.version_folder_conflict")
        default: String(localized: "usb_copy.log.reason.error_code", defaultValue: "error code \(code.errorCodeText)")
        }
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableEvent: String { eventDescription }
    var sortableLogType: String { logTypeName }
    var sortableTask: Int { taskID ?? -1 }
    var sortableError: String { errorText ?? "" }
}

struct USBCopyLogPage: nonisolated Decodable, Sendable {
    let count: Int
    let logList: [USBCopyLogEntry]

    enum CodingKeys: String, CodingKey {
        case count
        case logList = "log_list"
    }
}
