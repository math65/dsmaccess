//
//  OpenedFile.swift
//  dsmaccess
//
//  Files currently open on the NAS (SYNO.Core.FileHandle get), as the resource monitor's
//  "Accessed file" sub-tab presents them.
//
//  Three quirks observed on DSM 7.4 on 30/07/2026:
//  — `path` is relative to the share, has no leading slash, and **ends with the file name**:
//    showing `filename` and `path` side by side would repeat the name.
//  — `user` and `host` hold the string "-" for a NAS-local service, never an empty string
//    nor `null` — the same trap as `ProcessGroup`.
//  — `pid` arrives as a numeric **string**, where the other APIs of the module send a number.
//

import Foundation

struct OpenedFilePage: nonisolated Decodable, Sendable {
    let files: [OpenedFile]
    /// Total number of files open on the NAS, independent of the requested page.
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case files = "OpenedFiles"
        case total
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = try c.decodeIfPresent([OpenedFile].self, forKey: .files) ?? []
        total = c.flexInt(.total)
    }
}

struct OpenedFile: nonisolated Decodable, Sendable, Identifiable {
    let name: String?
    /// Path relative to the share, file name included.
    let path: String?
    /// Service holding the file open: "SMB", "Plex Media Server"…
    let service: String?
    /// Account that opened the file. `nil` for a NAS-local service.
    let account: String?
    /// Machine the access comes from. `nil` for a NAS-local service.
    let host: String?
    /// Process holding the file. Serves as identity and, for DSM, as the target to close.
    let processID: String?

    /// The NAS assigns no identifier: one process can hold several files, and one path can be
    /// open in several processes. Taken together, the two tell them apart.
    var id: String { [processID, path].compactMap { $0 }.joined(separator: "|") }

    var displayName: String { name ?? path ?? "" }

    /// Folder holding the file, without repeating its name. `nil` when the path contains no
    /// folder at all, rather than an empty string that would read as a value.
    var folder: String? {
        guard let path else { return nil }
        guard let separator = path.lastIndex(of: "/") else { return nil }
        let parent = String(path[path.startIndex..<separator])
        return parent.isEmpty ? nil : parent
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableName: String { displayName }
    var sortableFolder: String { folder ?? "" }
    var sortableService: String { service ?? "" }
    var sortableAccount: String { account ?? "" }
    var sortableHost: String { host ?? "" }

    enum CodingKeys: String, CodingKey {
        case filename, path, service, user, host, pid
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexString(.filename)
        path = c.flexString(.path)
        service = c.flexString(.service)
        account = Self.meaningful(c.flexString(.user))
        host = Self.meaningful(c.flexString(.host))
        processID = Self.meaningful(c.flexString(.pid))
    }

    /// DSM writes "-" when the value does not apply — a local service has neither an account
    /// nor an originating machine. Displayed as is, that string would pass for data coming
    /// from the NAS.
    private static func meaningful(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "-" ? nil : trimmed
    }
}
