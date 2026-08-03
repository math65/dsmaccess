//
//  HyperBackupVersion.swift
//  dsmaccess
//
//  Backup versions (SYNO.Backup.Version, version 2) and what the destination allows
//  (SYNO.Backup.Target).
//

import Foundation

/// Version outcomes observed on DSM 7.4: a completed backup, one cancelled mid-run, and the
/// one currently being written.
enum HyperBackupVersionStatus: String, Sendable {
    case success
    case cancelled = "cancel"
    case running = "backup"

    var localizedName: String {
        switch self {
        case .success: String(localized: "hyper_backup.version.status.success")
        case .cancelled: String(localized: "hyper_backup.version.status.cancelled")
        case .running: String(localized: "hyper_backup.version.status.running")
        }
    }
}

struct HyperBackupVersion: nonisolated Decodable, Equatable, Identifiable, Sendable {
    /// DSM sends the identifier as a string even though it reads as a number.
    let versionID: String
    let status: String
    let isLocked: Bool
    let hasHistory: Bool
    let canDelete: Bool
    let startTimestamp: Int?
    let completionTimestamp: Int?

    var id: String { versionID }

    private enum CodingKeys: String, CodingKey {
        case versionID = "version_id"
        case status
        case isLocked = "locked"
        case hasHistory = "has_history"
        case canDelete = "permit_delete"
        case startTimestamp = "timestamp"
        case completionTimestamp = "complete_time"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        versionID = try values.requiredFlexString(.versionID)
        status = try values.requiredFlexString(.status)
        isLocked = values.flexBool(.isLocked) ?? false
        hasHistory = values.flexBool(.hasHistory) ?? false
        canDelete = values.flexBool(.canDelete) ?? false
        startTimestamp = values.flexInt(.startTimestamp)
        completionTimestamp = values.flexInt(.completionTimestamp)
    }

    var knownStatus: HyperBackupVersionStatus? { HyperBackupVersionStatus(rawValue: status) }
    var statusDescription: String { knownStatus?.localizedName ?? status }

    /// DSM also sends preformatted local strings, which are not in the user's locale. The
    /// epoch values are formatted by the app instead.
    var startDate: Date? { startTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var completionDate: Date? {
        completionTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    var durationDescription: String {
        guard let startTimestamp, let completionTimestamp,
              completionTimestamp >= startTimestamp else {
            return String(localized: "common.value.not_available")
        }
        return Duration.seconds(completionTimestamp - startTimestamp)
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }

    var lockDescription: String {
        isLocked
            ? String(localized: "hyper_backup.version.lock.locked")
            : String(localized: "hyper_backup.version.lock.unlocked")
    }

    var sortableStatus: String { statusDescription }
    var sortableCompletion: Int { completionTimestamp ?? 0 }
    var sortableLock: String { lockDescription }
}

struct HyperBackupVersionList: nonisolated Decodable, Sendable {
    let versions: [HyperBackupVersion]

    private enum CodingKeys: String, CodingKey {
        case versions = "version_info_list"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        versions = try values.decodeIfPresent([HyperBackupVersion].self, forKey: .versions) ?? []
    }
}

/// What the destination supports. Read at run time so the module stays correct in front of a
/// destination type it has never been tested against.
struct HyperBackupTargetCapability: nonisolated Decodable, Equatable, Sendable {
    let supportsDownload: Bool
    let supportsFilter: Bool
    let supportsStatistics: Bool

    private enum CodingKeys: String, CodingKey {
        case supportsDownload = "support_download"
        case supportsFilter = "support_filter"
        case supportsStatistics = "support_statistics"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        supportsDownload = values.flexBool(.supportsDownload) ?? false
        supportsFilter = values.flexBool(.supportsFilter) ?? false
        supportsStatistics = values.flexBool(.supportsStatistics) ?? false
    }
}

struct HyperBackupTarget: nonisolated Decodable, Equatable, Sendable {
    let capability: HyperBackupTargetCapability?
    let hostName: String?
    let formatType: String?
    let isCompressed: Bool
    let isEncrypted: Bool
    let supportsMultipleVersions: Bool
    let lastIntegrityCheckTimestamp: Int?

    private enum CodingKeys: String, CodingKey {
        case capability
        case hostName = "host_name"
        case formatType = "format_type"
        case isCompressed = "data_comp"
        case isEncrypted = "data_enc"
        case supportsMultipleVersions = "support_multi_version"
        case lastIntegrityCheckTimestamp = "last_detect_time"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        capability = try values.decodeIfPresent(HyperBackupTargetCapability.self, forKey: .capability)
        hostName = values.flexString(.hostName)
        formatType = values.flexString(.formatType)
        isCompressed = values.flexBool(.isCompressed) ?? false
        isEncrypted = values.flexBool(.isEncrypted) ?? false
        supportsMultipleVersions = values.flexBool(.supportsMultipleVersions) ?? false
        lastIntegrityCheckTimestamp = values.flexInt(.lastIntegrityCheckTimestamp)
    }

    var lastIntegrityCheckDate: Date? {
        guard let lastIntegrityCheckTimestamp, lastIntegrityCheckTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(lastIntegrityCheckTimestamp))
    }
}
