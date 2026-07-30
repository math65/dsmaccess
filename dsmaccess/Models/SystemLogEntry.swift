//
//  SystemLogEntry.swift
//  dsmaccess
//
//  NAS system log (SYNO.Core.SyslogClient.Log list) and the auto block block list
//  (SYNO.Core.Security.AutoBlock.Rules list).
//
//  Contracts captured on DSM 7.4 on 2026/07/30. Four quirks:
//  — The log arrives under the `items` key, and each page carries the per-severity counts.
//    ⚠️ Those counts apply to the page received, not to the whole NAS log.
//  — The category lives in `logtype`, which the NAS has **already translated** into the DSM
//    account's language, and in `orginalLogType` (sic), which keeps the technical value. The
//    latter is the one read, so the app speaks its own language and not the DSM session's.
//  — An entry carries **no source address** at all: neither `from` nor `ip`.
//  — A blocked address with no expiry carries `expire_date` at 0, which the NAS still formats
//    as "1970/01/01": the integer is what counts.
//

import Foundation

/// Log requested from the NAS. ⚠️ `SYNO.Core.SyslogClient.Log` does not keep one log but
/// several, and without `logtype` it returns only the system one: on the development DS920+,
/// 6,997 system entries against more than 114,000 in total. The raw value is the one the NAS
/// expects, and the transfer logs are named after their protocol.
enum SystemLogKind: String, nonisolated Sendable, Hashable, Identifiable, CaseIterable {
    case system
    case connection
    case afp
    case cifs
    case fileStation = "filestation"
    case ftp
    case tftp
    case webdav

    var id: String { rawValue }

    /// Logs the NAS always keeps, with no setting to enable.
    static let always: [SystemLogKind] = [.system, .connection]

    /// Transfer logs, each one conditional on its protocol's logging being enabled.
    static let transfers: [SystemLogKind] = [.afp, .cifs, .fileStation, .ftp, .tftp, .webdav]

    /// Transfer logs do not have the same shape as the others: no severity, but the source
    /// address, the operation and the file size. The columns depend on this.
    var isTransfer: Bool { Self.transfers.contains(self) }
}

/// Auto block settings (SYNO.Core.Security.AutoBlock get/set): after how many failures, within
/// which window, and for how long the NAS refuses an address.
struct AutoBlockSettings: nonisolated Decodable, Sendable, Equatable {
    var isEnabled: Bool
    /// Number of failed sign-in attempts after which the address is blocked.
    var attempts: Int
    /// Window, in minutes, over which those failures are counted.
    var withinMinutes: Int
    /// Days after which a block expires. `0` means "never" — that is how DSM encodes the
    /// absence of an expiry, not by a missing value.
    var expiryDays: Int

    var expires: Bool { expiryDays > 0 }

    enum CodingKeys: String, CodingKey {
        case enable, attempts
        case withinMinutes = "within_mins"
        case expiryDays = "expire_day"
    }

    nonisolated init(isEnabled: Bool, attempts: Int, withinMinutes: Int, expiryDays: Int) {
        self.isEnabled = isEnabled
        self.attempts = attempts
        self.withinMinutes = withinMinutes
        self.expiryDays = expiryDays
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = c.flexBool(.enable) ?? false
        attempts = c.flexInt(.attempts) ?? 0
        withinMinutes = c.flexInt(.withinMinutes) ?? 0
        expiryDays = c.flexInt(.expiryDays) ?? 0
    }

    /// Bounds DSM enforces on its own form. A threshold outside them would be rejected.
    static let attemptsRange = 1...100
    static let withinMinutesRange = 1...1440
    static let expiryDaysRange = 1...2000
}

/// Export format offered by the NAS. The raw value is the one it expects.
enum SystemLogExportFormat: String, nonisolated Sendable, CaseIterable, Identifiable {
    case csv
    case html

    var id: String { rawValue }

    /// Extension of the file offered when saving.
    var fileExtension: String { rawValue }
}

/// Protocols whose transfers the NAS logs (SYNO.Core.SyslogClient.FileTransfer get). This
/// setting decides which transfer logs exist: asking for a disabled log returns zero entries
/// without an error, which would read as an empty log.
struct FileTransferLogging: nonisolated Decodable, Sendable, Equatable {
    let enabled: Set<SystemLogKind>

    /// Protocols this setting covers, in the order the screen presents them.
    static let protocols = SystemLogKind.transfers

    nonisolated init(enabled: Set<SystemLogKind>) {
        self.enabled = enabled
    }

    /// All six fields are always sent, including those at their current value: verified on
    /// DSM 7.4, `set` ignores missing fields, but sending them all removes the ambiguity.
    var parameters: [String: Bool] {
        Dictionary(
            uniqueKeysWithValues: Self.protocols.map { ($0.rawValue, enabled.contains($0)) }
        )
    }

    enum CodingKeys: String, CodingKey {
        case afp, cifs, filestation, ftp, tftp, webdav
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var active: Set<SystemLogKind> = []
        let flags: [(CodingKeys, SystemLogKind)] = [
            (.afp, .afp), (.cifs, .cifs), (.filestation, .fileStation),
            (.ftp, .ftp), (.tftp, .tftp), (.webdav, .webdav),
        ]
        for (key, kind) in flags where c.flexBool(key) == true {
            active.insert(kind)
        }
        enabled = active
    }
}

struct SystemLogPage: nonisolated Decodable, Sendable {
    let entries: [SystemLogEntry]
    /// Number of entries the NAS keeps, independent of the page requested.
    let total: Int?
    /// Per-severity counts **for the page received**, returned by the NAS along with it.
    let errorCount: Int?
    let warningCount: Int?
    let infoCount: Int?

    enum CodingKeys: String, CodingKey {
        case items, total
        case errorCount = "errorCount"
        case warningCount = "warnCount"
        case infoCount = "infoCount"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([SystemLogEntry].self, forKey: .items) ?? []
        // The NAS assigns no identifier and two entries can share the same second, level and
        // message: the rank within the page is the only identity that tells them apart.
        entries = decoded.enumerated().map { offset, entry in
            var positioned = entry
            positioned.position = offset
            return positioned
        }
        total = c.flexInt(.total)
        errorCount = c.flexInt(.errorCount)
        warningCount = c.flexInt(.warningCount)
        infoCount = c.flexInt(.infoCount)
    }
}

struct SystemLogEntry: nonisolated Decodable, Sendable, Identifiable {
    /// Rank within the page returned, assigned at decoding time. The NAS provides no key.
    fileprivate(set) var position = 0
    /// Raw NAS timestamp, in "yyyy/MM/dd HH:mm:ss" format.
    let rawTime: String?
    /// `nil` in the transfer logs, which assign no severity at all. An "unknown level" column
    /// there would be a misreading.
    let level: Level?
    /// Technical, untranslated category: "system". Used as the display key.
    let technicalCategory: String?
    /// Category as the NAS translated it, in the DSM account's language. Fallback when the
    /// technical value is unknown to the app.
    let translatedCategory: String?
    /// Account involved. The system log and the connection log write it in `who`, the transfer
    /// logs in `username`.
    let account: String?
    let message: String
    /// Source address, present in the transfer logs only.
    let address: String?
    /// Operation recorded by a transfer log: read, write, delete…
    let operation: String?
    /// Size of the transferred file, in bytes. `nil` for a folder or outside a transfer.
    let fileSize: Int64?
    /// True when the entry concerns a folder and not a file.
    let isDirectory: Bool

    var id: Int { position }

    /// Renumbers the entry starting from the given rank. Later pages of the log start back at
    /// zero: without this offset, the second page would carry the first page's identifiers and
    /// the table would confuse its rows.
    nonisolated func renumbered(from start: Int) -> SystemLogEntry {
        var copy = self
        copy.position += start
        return copy
    }

    /// Timestamp rendered in the Mac's language and time zone. DSM does not state the time zone
    /// of its value: it is read as local, which is correct as long as the NAS and the Mac share
    /// the same one.
    var recordedAt: Date? {
        guard let rawTime else { return nil }
        return Self.nasFormatter.date(from: rawTime)
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted.
    var sortableDate: Date { recordedAt ?? .distantPast }
    var sortableAccount: String { account ?? "" }
    var sortableMessage: String { message }
    var sortableAddress: String { address ?? "" }
    var sortableOperation: String { operation ?? "" }
    /// An entry with no size sorts before the others rather than preventing the sort.
    var sortableSize: Int64 { fileSize ?? -1 }
    /// Sorted by decreasing severity, not alphabetically. An entry with no severity sorts
    /// before the informational ones.
    var sortableLevel: Int { level?.severity ?? -1 }

    /// Severity as DSM encodes it: three short values. A fourth one would be a DSM evolution,
    /// kept as is rather than forced into one of the existing ones.
    enum Level: nonisolated Sendable, Equatable, Hashable {
        case info
        case warning
        case error
        case other(String)

        var severity: Int {
            switch self {
            case .info: 0
            case .other: 1
            case .warning: 2
            case .error: 3
            }
        }

        nonisolated init(rawValue: String?) {
            switch rawValue?.lowercased() {
            case "info", "information": self = .info
            case "warn", "warning": self = .warning
            case "err", "error", "crit", "critical": self = .error
            case let value?: self = .other(value)
            case nil: self = .other("")
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case time, level, logtype, who, username, ip, cmd, filesize, isdir
        case technicalCategory = "orginalLogType"
        case message = "descr"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawTime = c.flexString(.time)
        // Absent from the transfer logs: an invented severity there would be wrong.
        level = c.flexString(.level).map { Level(rawValue: $0) }
        technicalCategory = c.flexString(.technicalCategory).flatMap { $0.isEmpty ? nil : $0 }
        translatedCategory = c.flexString(.logtype).flatMap { $0.isEmpty ? nil : $0 }
        account = Self.meaningful(c.flexString(.who) ?? c.flexString(.username))
        message = c.flexString(.message) ?? ""
        address = Self.meaningful(c.flexString(.ip))
        operation = Self.meaningful(c.flexString(.cmd))
        // A folder has no useful size, and the NAS writes zero there.
        isDirectory = c.flexBool(.isdir) ?? false
        fileSize = isDirectory ? nil : c.flexInt64(.filesize).flatMap { $0 > 0 ? $0 : nil }
    }

    nonisolated private static func meaningful(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "-" ? nil : trimmed
    }

    private static let nasFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Single-digit components accepted as well as padded ones: this API sends padded
        // values, but DSM's own web client reads both forms.
        formatter.dateFormat = "yyyy/M/d H:m:s"
        return formatter
    }()
}

/// An address from the auto block block list.
struct BlockedAddress: nonisolated Decodable, Sendable, Identifiable {
    let address: String
    /// Country inferred by DSM. Empty when geolocation does not resolve.
    let country: String?
    let isPublic: Bool
    let blockedAt: Date?
    /// `nil` when the block does not expire. The NAS then sends 0, which it formats itself as
    /// 1970: the formatted date is therefore never read.
    let expiresAt: Date?

    var id: String { address }

    var sortableCountry: String { country ?? "" }
    var sortableBlockedAt: Date { blockedAt ?? .distantPast }
    /// A block with no expiry sorts after the others: it is the longest-lasting one.
    var sortableExpiry: Date { expiresAt ?? .distantFuture }

    enum CodingKeys: String, CodingKey {
        case ip, country
        case isPublic = "is_public_ip"
        case blockedAt = "record_date"
        case expiresAt = "expire_date"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.requiredFlexString(.ip)
        country = c.flexString(.country).flatMap { $0.isEmpty ? nil : $0 }
        isPublic = c.flexBool(.isPublic) ?? false
        blockedAt = c.flexInt64(.blockedAt).flatMap(Self.date)
        expiresAt = c.flexInt64(.expiresAt).flatMap(Self.date)
    }

    /// Zero is not a date: it is how DSM says "no expiry", and for `record_date` the absence
    /// of a value.
    nonisolated private static func date(_ timestamp: Int64) -> Date? {
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

struct BlockedAddressPage: nonisolated Decodable, Sendable {
    let addresses: [BlockedAddress]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case addresses = "ip_info"
        case total
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addresses = try c.decodeIfPresent([BlockedAddress].self, forKey: .addresses) ?? []
        total = c.flexInt(.total)
    }
}
