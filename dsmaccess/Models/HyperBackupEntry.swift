//
//  HyperBackupEntry.swift
//  dsmaccess
//
//  What a backup version holds, as listed by the DSM restore browser
//  (SYNO.SDS.Backup.Client.Explore.Folder and .File).
//

import Foundation

struct HyperBackupEntry: nonisolated Decodable, Equatable, Identifiable, Sendable {
    let name: String
    /// Path relative to the backup root, with no leading slash. Both list methods answer
    /// error 4400 when the path starts with one.
    let path: String
    let type: String
    let size: Int?
    let modificationTimestamp: Int?
    let isDamaged: Bool
    /// DSM raises this when putting the entry back over its original would not be safe.
    let warnsAgainstRestore: Bool

    var id: String { path }

    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case type
        case size
        case modificationTimestamp = "mtime"
        case isDamaged = "is_bad"
        case warnsAgainstRestore = "restore_unsafe_warn"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        path = try values.requiredFlexString(.path)
        type = values.flexString(.type) ?? "File"
        size = values.flexInt(.size)
        modificationTimestamp = values.flexInt(.modificationTimestamp)
        isDamaged = values.flexBool(.isDamaged) ?? false
        warnsAgainstRestore = values.flexBool(.warnsAgainstRestore) ?? false
    }

    var isFolder: Bool { type == "Folder" }

    var kindDescription: String {
        isFolder
            ? String(localized: "hyper_backup.restore.kind.folder")
            : String(localized: "hyper_backup.restore.kind.file")
    }

    var modificationDate: Date? {
        guard let modificationTimestamp, modificationTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(modificationTimestamp))
    }

    /// Shown and spoken alongside the row, so damage is never carried by an icon alone.
    /// Nil for the healthy case: repeating "readable" on every row is noise.
    var warningDescription: String? {
        if isDamaged { return String(localized: "hyper_backup.restore.condition.damaged") }
        if warnsAgainstRestore { return String(localized: "hyper_backup.restore.condition.unsafe") }
        return nil
    }

    /// Value of the size column, nil for a folder: the size of its own record says nothing
    /// useful about what it holds.
    var sizeDescription: String? {
        guard !isFolder, let size else { return nil }
        return Int64(size).formatted(.byteCount(style: .file))
    }

    /// Value of the modification date column.
    var modificationDescription: String? {
        modificationDate?.formatted(date: .abbreviated, time: .shortened)
    }
}

/// `File.list` wraps its entries, unlike `Folder.list` which answers a bare array.
struct HyperBackupEntryPage: nonisolated Decodable, Sendable {
    let entries: [HyperBackupEntry]

    private enum CodingKeys: String, CodingKey {
        case entries = "files"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decodeIfPresent([HyperBackupEntry].self, forKey: .entries) ?? []
    }
}

/// Where a restore puts its copy: a share, named for the user, plus the physical path the
/// API insists on.
struct HyperBackupRestoreDestination: Equatable, Identifiable, Sendable {
    let name: String
    /// `/volume1/Documents`, never the `/Documents` share path — `copy` rejects the latter.
    let physicalPath: String

    var id: String { physicalPath }
}
