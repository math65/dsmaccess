//
//  ResourceMonitorLogEntry.swift
//  dsmaccess
//
//  Resource monitor history (SYNO.ResourceMonitor.Log list): the alerts the NAS recorded
//  when a resource crossed a threshold.
//
//  Two quirks observed on DSM 7.4:
//  — `time` is **not** zero-padded, unlike `CurrentConnection`: the web client reads it with
//    “Y/n/j G:i:s”, so “2026/7/30 9:05:12” is a normal value. A rigid “yyyy/MM/dd” format
//    would not recognize it.
//  — `level` arrives in English in the payload; it is the client that translates. Displayed
//    as is, the screen would speak English to a French user.
//

import Foundation

/// Resource monitor settings (SYNO.ResourceMonitor.Setting get). DSM exposes only one:
/// history recording. Without it, the log stays empty indefinitely.
struct ResourceMonitorSetting: nonisolated Decodable, Sendable {
    let historyEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case historyEnabled = "enable_history"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        historyEnabled = try c.requiredFlexBool(.historyEnabled)
    }
}

struct ResourceMonitorLogPage: nonisolated Decodable, Sendable {
    let entries: [ResourceMonitorLogEntry]
    /// Total number of entries kept by the NAS, independent of the requested page.
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case logs, total
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([ResourceMonitorLogEntry].self, forKey: .logs) ?? []
        // The NAS assigns no identifier and two identical alerts can land within the same
        // second: the rank within the page is the only identity that tells them apart.
        entries = decoded.enumerated().map { offset, entry in
            var positioned = entry
            positioned.position = offset
            return positioned
        }
        total = c.flexInt(.total)
    }
}

struct ResourceMonitorLogEntry: nonisolated Decodable, Sendable, Identifiable {
    /// Rank within the returned page, assigned at decoding time. The NAS provides no key.
    fileprivate(set) var position = 0
    /// Raw NAS timestamp, whose components are not zero-padded.
    let rawTime: String?
    let level: Level
    /// Description of the alert, exactly as the NAS wrote it.
    let event: String?

    var id: Int { position }

    /// Timestamp rendered in the Mac's language and time zone. DSM does not state the time
    /// zone of its value: it is read as local, which is correct as long as the NAS and the Mac
    /// share the same one. The raw string serves as a fallback rather than displaying nothing.
    var recordedAt: Date? {
        guard let rawTime else { return nil }
        return Self.nasFormatter.date(from: rawTime)
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableDate: Date { recordedAt ?? .distantPast }
    var sortableEvent: String { event ?? "" }
    /// Sorted by decreasing severity and not alphabetically: ranking “Critical” after
    /// “Information” would make no sense to the user.
    var sortableLevel: Int { level.severity }

    /// Severity of the alert. DSM only knows three; a fourth value would be a DSM evolution,
    /// kept as is rather than forcibly filed under one of them.
    enum Level: nonisolated Sendable, Equatable {
        case information
        case warning
        case critical
        case other(String)

        /// Increasing severity order, for sorting the column.
        var severity: Int {
            switch self {
            case .information: 0
            case .other: 1
            case .warning: 2
            case .critical: 3
            }
        }

        nonisolated init(rawValue: String?) {
            switch rawValue?.lowercased() {
            case "information", "info": self = .information
            case "warning", "warn": self = .warning
            case "critical", "error": self = .critical
            case let value?: self = .other(value)
            case nil: self = .other("")
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case time, level, event
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawTime = c.flexString(.time)
        level = Level(rawValue: c.flexString(.level))
        event = c.flexString(.event).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Single-digit components in the pattern: DateFormatter then accepts both forms, padded
    /// or not. `CurrentConnection` receives a padded timestamp and uses a rigid pattern; the
    /// two APIs of the same module are not written the same way.
    private static let nasFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/M/d H:m:s"
        return formatter
    }()
}
