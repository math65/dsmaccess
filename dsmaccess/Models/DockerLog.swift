//
//  DockerLog.swift
//  dsmaccess
//
//  Container Manager's own event log (SYNO.Docker.Log).
//

import Foundation

struct DockerLogEntry: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let event: String
    let level: String
    let logType: String?
    let time: String
    let user: String?

    /// The API exposes no identifier; the tuple is stable enough for a read-only list.
    var id: String { "\(time)|\(level)|\(event.hashValue)" }

    enum CodingKeys: String, CodingKey {
        case event
        case level
        case logType = "log_type"
        case time
        case user
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        event = values.flexString(.event) ?? ""
        level = values.flexString(.level) ?? ""
        logType = values.flexString(.logType)
        time = values.flexString(.time) ?? ""
        user = values.flexString(.user).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Observed values on DSM 7.4: `info` and `err` (not `error`).
    var localizedLevel: String {
        switch level.lowercased() {
        case "info": String(localized: "common.level.information")
        case "warn", "warning": String(localized: "common.level.warning")
        case "err", "error": String(localized: "common.level.error")
        default: level
        }
    }
}

struct DockerLogPage: nonisolated Decodable, Sendable {
    let entries: [DockerLogEntry]
    let total: Int
    let errorCount: Int?
    let warningCount: Int?
    let infoCount: Int?

    enum CodingKeys: String, CodingKey {
        case entries = "logs"
        case total
        case errorCount = "error_count"
        case warningCount = "warn_count"
        case infoCount = "info_count"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decodeIfPresent([DockerLogEntry].self, forKey: .entries) ?? []
        total = values.flexInt(.total) ?? entries.count
        errorCount = values.flexInt(.errorCount)
        warningCount = values.flexInt(.warningCount)
        infoCount = values.flexInt(.infoCount)
    }
}

/// Severities the log can be filtered on. Raw values are what the API expects in `loglevel`,
/// measured on DSM 7.4: full words, unlike the `info`/`err` the entries themselves carry.
/// The empty string means every level.
enum DockerLogLevelFilter: String, CaseIterable, Identifiable, Sendable {
    case all = ""
    case information
    case warning
    case error

    var id: Self { self }

    var localizedName: String {
        switch self {
        case .all: String(localized: "common.filter.all")
        case .information: String(localized: "common.level.information")
        case .warning: String(localized: "common.level.warning")
        case .error: String(localized: "common.level.error")
        }
    }
}

enum DockerLogExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case html

    var id: Self { self }

    var fileExtension: String { rawValue }
}
