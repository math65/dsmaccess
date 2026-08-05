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

    /// A folder carries the size of its own record, which says nothing useful about what it
    /// contains, so only files show a size.
    var sizeDescription: String {
        guard !isFolder, let size else { return String(localized: "common.value.not_available") }
        return Int64(size).formatted(.byteCount(style: .file))
    }

    var modificationDate: Date? {
        guard let modificationTimestamp, modificationTimestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(modificationTimestamp))
    }

    var modificationDescription: String {
        guard let modificationDate else { return String(localized: "common.value.not_available") }
        return modificationDate.formatted(date: .abbreviated, time: .shortened)
    }

    /// Spoken alongside the row so damage is never carried by an icon alone.
    var conditionDescription: String {
        if isDamaged { return String(localized: "hyper_backup.restore.condition.damaged") }
        if warnsAgainstRestore { return String(localized: "hyper_backup.restore.condition.unsafe") }
        return String(localized: "hyper_backup.restore.condition.readable")
    }

    var sortableKind: String { kindDescription }
    var sortableSize: Int { isFolder ? -1 : (size ?? 0) }
    var sortableModification: Int { modificationTimestamp ?? 0 }
    var sortableCondition: String { conditionDescription }
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
