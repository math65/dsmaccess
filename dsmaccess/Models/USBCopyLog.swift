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
}

struct USBCopyLogPage: nonisolated Decodable, Sendable {
    let count: Int
    let logList: [USBCopyLogEntry]

    enum CodingKeys: String, CodingKey {
        case count
        case logList = "log_list"
    }
}
