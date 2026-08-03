//
//  HyperBackupLog.swift
//  dsmaccess
//
//  Task log and transfer statistics (SYNO.SDS.Backup.Client.Common.Log and .Statistic).
//

import Foundation

enum HyperBackupLogLevel: Sendable {
    case information
    case warning
    case error

    /// Only `info` and `err` were observed on DSM 7.4. The warning spellings are mapped for
    /// display, and any other value falls back to the raw DSM token rather than being guessed.
    static func named(_ raw: String) -> HyperBackupLogLevel? {
        switch raw.lowercased() {
        case "info": .information
        case "warn", "warning": .warning
        case "err", "error": .error
        default: nil
        }
    }

    var localizedName: String {
        switch self {
        case .information: String(localized: "hyper_backup.log.level.information")
        case .warning: String(localized: "hyper_backup.log.level.warning")
        case .error: String(localized: "hyper_backup.log.level.error")
        }
    }
}

struct HyperBackupLogEntry: nonisolated Decodable, Equatable, Identifiable, Sendable {
    let time: String
    let level: String
    let event: String
    let user: String?

    /// The API paginates without giving the rows an identifier; the timestamp and the message
    /// together are what distinguishes one line from the next.
    var id: String { "\(time)|\(event)" }

    private enum CodingKeys: String, CodingKey {
        case time, level, event, user
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        time = values.flexString(.time) ?? ""
        level = values.flexString(.level) ?? ""
        event = try values.requiredFlexString(.event)
        user = values.flexString(.user)
    }

    var knownLevel: HyperBackupLogLevel? { HyperBackupLogLevel.named(level) }
    var levelDescription: String { knownLevel?.localizedName ?? level }

    /// DSM sends `2026/08/03 04:42:19` rather than an epoch. It is reformatted for the user's
    /// locale when it parses, and shown untouched when it does not.
    var date: Date? { Self.parser.date(from: time) }

    var timeDescription: String {
        guard let date else { return time }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    var sortableTime: String { time }
    var sortableLevel: String { levelDescription }

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()
}

struct HyperBackupLogPage: nonisolated Decodable, Sendable {
    let entries: [HyperBackupLogEntry]
    let total: Int
    let errorCount: Int
    let warningCount: Int
    let informationCount: Int

    private enum CodingKeys: String, CodingKey {
        case entries = "log_list"
        case total
        case errorCount = "error_count"
        case warningCount = "warn_count"
        case informationCount = "info_count"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decodeIfPresent([HyperBackupLogEntry].self, forKey: .entries) ?? []
        total = values.flexInt(.total) ?? 0
        errorCount = values.flexInt(.errorCount) ?? 0
        warningCount = values.flexInt(.warningCount) ?? 0
        informationCount = values.flexInt(.informationCount) ?? 0
    }
}

/// One run's figures. DSM returns the source and target sides in two parallel arrays holding
/// the previous run then the latest one; an entry whose `end_time` is zero means "no such run".
struct HyperBackupRunStatistics: Equatable, Sendable {
    let endTimestamp: Int
    let newCount: Int
    let modifiedCount: Int
    let deletedCount: Int
    let sourceSize: Int64
    let targetSize: Int64

    var endDate: Date? {
        guard endTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(endTimestamp))
    }
}

struct HyperBackupStatistics: nonisolated Decodable, Equatable, Sendable {
    let previousRun: HyperBackupRunStatistics?
    let latestRun: HyperBackupRunStatistics?

    private enum CodingKeys: String, CodingKey {
        case sourceRuns = "source_previous_next_list"
        case targetRuns = "target_previous_next_list"
    }

    private struct SourceRun: nonisolated Decodable, Sendable {
        let endTime: Int
        let newCount: Int
        let modifyCount: Int
        let deleteCount: Int
        let sourceSize: Int64

        private enum CodingKeys: String, CodingKey {
            case endTime = "end_time"
            case newCount = "new_count"
            case modifyCount = "modify_count"
            case deleteCount = "delete_count"
            case sourceSize = "source_size"
        }

        nonisolated init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            endTime = values.flexInt(.endTime) ?? 0
            newCount = values.flexInt(.newCount) ?? 0
            modifyCount = values.flexInt(.modifyCount) ?? 0
            deleteCount = values.flexInt(.deleteCount) ?? 0
            sourceSize = values.flexInt64(.sourceSize) ?? 0
        }
    }

    private struct TargetRun: nonisolated Decodable, Sendable {
        let endTime: Int
        let targetSize: Int64

        private enum CodingKeys: String, CodingKey {
            case endTime = "end_time"
            case targetSize = "target_size"
        }

        nonisolated init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            endTime = values.flexInt(.endTime) ?? 0
            targetSize = values.flexInt64(.targetSize) ?? 0
        }
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let sources = try values.decodeIfPresent([SourceRun].self, forKey: .sourceRuns) ?? []
        let targets = try values.decodeIfPresent([TargetRun].self, forKey: .targetRuns) ?? []

        func run(at index: Int) -> HyperBackupRunStatistics? {
            guard index < sources.count else { return nil }
            let source = sources[index]
            guard source.endTime > 0 else { return nil }
            let target = index < targets.count ? targets[index] : nil
            return HyperBackupRunStatistics(
                endTimestamp: source.endTime,
                newCount: source.newCount,
                modifiedCount: source.modifyCount,
                deletedCount: source.deleteCount,
                sourceSize: source.sourceSize,
                targetSize: target?.targetSize ?? 0
            )
        }

        previousRun = sources.count > 1 ? run(at: 0) : nil
        latestRun = sources.isEmpty ? nil : run(at: sources.count - 1)
    }
}
