//
//  FileStationItem.swift
//  dsmaccess
//
//  An item (folder or file) returned by SYNO.FileStation.List, whether a root shared
//  folder (method=list_share) or the contents of a folder (method=list).
//

import Foundation

/// Folder or file as described by File Station.
struct FileStationItem: nonisolated Decodable, Equatable, Identifiable, Sendable {
    /// Displayed name (e.g. "photo", "holidays.jpg").
    let name: String
    /// Absolute path on the NAS (e.g. "/photo/holidays.jpg") — used as the navigation key.
    let path: String
    /// True if this is a folder (hence expandable), false if it is a file.
    let isdir: Bool
    /// Optional metadata (size, dates) requested through the `additional` parameter.
    let additional: Additional?
    /// Contents returned by `goto_path`, when requested.
    let children: FileStationChildren?

    var id: String { path }

    /// Volume figures as text, for the virtual folders table. A mount point DSM reports
    /// nothing about shows a dash rather than an empty cell, which would read as a value.
    var freeSpaceDescription: String {
        guard let freeSpace = additional?.volumeStatus?.freeSpace else { return "—" }
        return freeSpace.formatted(.byteCount(style: .file))
    }

    var volumeAccessDescription: String {
        guard let isReadOnly = additional?.volumeStatus?.isReadOnly else { return "—" }
        return isReadOnly
            ? String(localized: "common.permission.read_only")
            : String(localized: "files.info.permission.read_write")
    }

    private enum CodingKeys: String, CodingKey {
        case name, path, isdir, additional, children
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.requiredFlexString(.name)
        path = try container.requiredFlexString(.path)
        isdir = try container.requiredFlexBool(.isdir)
        additional = try container.decodeIfPresent(Additional.self, forKey: .additional)
        children = try container.decodeIfPresent(FileStationChildren.self, forKey: .children)
    }

    struct Additional: nonisolated Decodable, Equatable, Sendable {
        /// Size in bytes (files only).
        let size: Int64?
        let time: TimeInfo?
        let owner: OwnerInfo?
        let permission: PermissionInfo?
        let type: String?
        let realPath: String?
        let mountPointType: String?
        let volumeStatus: VolumeStatus?

        enum CodingKeys: String, CodingKey {
            case size, time, owner, type
            case permission = "perm"
            case realPath = "real_path"
            case mountPointType = "mount_point_type"
            case volumeStatus = "volume_status"
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            size = container.flexInt64(.size)
            time = try container.decodeIfPresent(TimeInfo.self, forKey: .time)
            owner = try container.decodeIfPresent(OwnerInfo.self, forKey: .owner)
            permission = try container.decodeIfPresent(PermissionInfo.self, forKey: .permission)
            type = container.flexString(.type)
            realPath = container.flexString(.realPath)
            mountPointType = container.flexString(.mountPointType)
            volumeStatus = try container.decodeIfPresent(VolumeStatus.self, forKey: .volumeStatus)
        }
    }

    struct TimeInfo: nonisolated Decodable, Equatable, Sendable {
        /// Last modification date, in seconds since the Unix epoch.
        let mtime: Int?
        let atime: Int?
        let ctime: Int?
        let crtime: Int?

        private enum CodingKeys: String, CodingKey {
            case mtime, atime, ctime, crtime
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mtime = container.flexInt(.mtime)
            atime = container.flexInt(.atime)
            ctime = container.flexInt(.ctime)
            crtime = container.flexInt(.crtime)
        }
    }

    struct OwnerInfo: nonisolated Decodable, Equatable, Sendable {
        let user: String?
        let group: String?
        let uid: Int?
        let gid: Int?

        private enum CodingKeys: String, CodingKey {
            case user, group, uid, gid
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            user = container.flexString(.user)
            group = container.flexString(.group)
            uid = container.flexInt(.uid)
            gid = container.flexInt(.gid)
        }
    }

    struct PermissionInfo: nonisolated Decodable, Equatable, Sendable {
        let posix: Int?
        let acl: ACLInfo?
        let shareRight: String?
        let advancedRight: AdvancedRight?
        let aclEnabled: Bool?
        let isACLMode: Bool?

        enum CodingKeys: String, CodingKey {
            case posix, acl
            case shareRight = "share_right"
            case advancedRight = "adv_right"
            case aclEnabled = "acl_enable"
            case isACLMode = "is_acl_mode"
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            posix = container.flexInt(.posix)
            acl = try container.decodeIfPresent(ACLInfo.self, forKey: .acl)
            shareRight = container.flexString(.shareRight)
            advancedRight = try container.decodeIfPresent(AdvancedRight.self, forKey: .advancedRight)
            aclEnabled = container.flexBool(.aclEnabled)
            isACLMode = container.flexBool(.isACLMode)
        }
    }

    struct ACLInfo: nonisolated Decodable, Equatable, Sendable {
        let append: Bool?
        let read: Bool?
        let write: Bool?
        let delete: Bool?
        let execute: Bool?

        enum CodingKeys: String, CodingKey {
            case append, read, write
            case delete = "del"
            case execute = "exec"
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            append = container.flexBool(.append)
            read = container.flexBool(.read)
            write = container.flexBool(.write)
            delete = container.flexBool(.delete)
            execute = container.flexBool(.execute)
        }
    }

    struct AdvancedRight: nonisolated Decodable, Equatable, Sendable {
        let disablesDownload: Bool?
        let disablesList: Bool?
        let disablesModify: Bool?

        enum CodingKeys: String, CodingKey {
            case disablesDownload = "disable_download"
            case disablesList = "disable_list"
            case disablesModify = "disable_modify"
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            disablesDownload = container.flexBool(.disablesDownload)
            disablesList = container.flexBool(.disablesList)
            disablesModify = container.flexBool(.disablesModify)
        }
    }

    struct VolumeStatus: nonisolated Decodable, Equatable, Sendable {
        let freeSpace: Int64?
        let totalSpace: Int64?
        let isReadOnly: Bool?

        enum CodingKeys: String, CodingKey {
            case freeSpace = "freespace"
            case totalSpace = "totalspace"
            case isReadOnly = "readonly"
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            freeSpace = container.flexInt64(.freeSpace)
            totalSpace = container.flexInt64(.totalSpace)
            isReadOnly = container.flexBool(.isReadOnly)
        }
    }
}

struct FileStationChildren: nonisolated Decodable, Equatable, Sendable {
    let total: Int
    let offset: Int
    let files: [FileStationItem]

    private enum CodingKeys: String, CodingKey {
        case total, offset, files
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decode([FileStationItem].self, forKey: .files)
        total = container.flexInt(.total) ?? files.count
        offset = container.flexInt(.offset) ?? 0
    }
}

extension FileStationItem {
    var supportsThumbnailPreview: Bool {
        guard !isdir else { return false }
        let supportedExtensions: Set<String> = [
            "bmp", "gif", "heic", "jpeg", "jpg", "png", "tif", "tiff", "webp",
        ]
        return supportedExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// Secondary line for a file: "2.3 MB · 12 Mar 2024" (nil for a folder).
    var detailText: String? {
        guard !isdir else { return nil }
        var parts: [String] = []
        if let size = additional?.size {
            parts.append(size.formatted(.byteCount(style: .file)))
        }
        if let mtime = additional?.time?.mtime {
            let date = Date(timeIntervalSince1970: TimeInterval(mtime))
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Name of the file materialized on the Mac during a download or a drop into the Finder:
    /// DSM delivers a folder as a ZIP archive.
    /// `nonisolated`: read by the promise delegates outside the MainActor.
    nonisolated var promisedFileName: String {
        isdir ? "\(name).zip" : name
    }

    /// Full label read by VoiceOver: "photo, folder" or "a.jpg, file, 2.3 MB · 12 Mar 2024".
    var accessibilityLabel: String {
        let kind = isdir ? String(localized: "files.item.kind.folder") : String(localized: "files.item.kind.file")
        var label = "\(name), \(kind)"
        if let detail = detailText {
            label += ", \(detail)"
        }
        return label
    }
}

extension Array where Element == FileStationItem {
    /// Display order: folders before files, then by name using a locale-aware comparison.
    func sortedForBrowsing() -> [FileStationItem] {
        sorted { lhs, rhs in
            if lhs.isdir != rhs.isdir { return lhs.isdir && !rhs.isdir }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Payload of `method=list_share`: the shared folders at the root.
struct FileStationShares: nonisolated Decodable, Sendable {
    let total: Int
    let offset: Int
    let shares: [FileStationItem]

    private enum CodingKeys: String, CodingKey {
        case total, offset, shares
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shares = try container.decode([FileStationItem].self, forKey: .shares)
        total = container.flexInt(.total) ?? shares.count
        offset = container.flexInt(.offset) ?? 0
    }
}

/// Payload of `method=list`: the contents of a folder.
struct FileStationFiles: nonisolated Decodable, Sendable {
    let total: Int
    let offset: Int
    let files: [FileStationItem]

    private enum CodingKeys: String, CodingKey {
        case total, offset, files
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decode([FileStationItem].self, forKey: .files)
        total = container.flexInt(.total) ?? files.count
        offset = container.flexInt(.offset) ?? 0
    }
}

struct FileStationCreatedFolders: nonisolated Decodable, Sendable {
    let folders: [FileStationItem]
}

struct FileStationSearchTask: nonisolated Decodable, Sendable {
    let taskid: String
}

struct FileStationSearchResults: nonisolated Decodable, Sendable {
    let total: Int
    let offset: Int
    let files: [FileStationItem]
    let finished: Bool

    private enum CodingKeys: String, CodingKey {
        case total, offset, files, finished
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        files = try container.decode([FileStationItem].self, forKey: .files)
        total = container.flexInt(.total) ?? files.count
        offset = container.flexInt(.offset) ?? 0
        finished = try container.requiredFlexBool(.finished)
    }
}

struct FileStationFavorites: nonisolated Decodable, Sendable {
    let total: Int
    let offset: Int
    let favorites: [FileStationFavorite]

    private enum CodingKeys: String, CodingKey {
        case total, offset, favorites
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favorites = try container.decode([FileStationFavorite].self, forKey: .favorites)
        total = container.flexInt(.total) ?? favorites.count
        offset = container.flexInt(.offset) ?? 0
    }
}

struct FileStationFavorite: nonisolated Decodable, Equatable, Identifiable, Sendable {
    let path: String
    let name: String
    let status: String?
    let isDirectory: Bool?
    let additional: FileStationItem.Additional?

    var id: String { path }
    var isAvailable: Bool { status != "broken" }

    /// The readable state lives here rather than in the view: the table shows it as a word of
    /// its own, never as a color or an icon alone.
    var statusDescription: String {
        isAvailable
            ? String(localized: "favorites.status.available")
            : String(localized: "common.status.unavailable")
    }

    private enum CodingKeys: String, CodingKey {
        case path, name, status, additional
        case isDirectory = "isdir"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.requiredFlexString(.path)
        name = try container.requiredFlexString(.name)
        status = container.flexString(.status)
        isDirectory = container.flexBool(.isDirectory)
        additional = try container.decodeIfPresent(FileStationItem.Additional.self, forKey: .additional)
    }
}

/// Response of `SYNO.FileStation.CopyMove` `method=start`: the task identifier to follow.
struct CopyMoveTask: nonisolated Decodable, Sendable {
    let taskid: String
}

struct FileOperationTask: nonisolated Decodable, Sendable {
    let taskid: String
}

/// Response of `SYNO.FileStation.Sharing` `method=create`: the share links created.
struct SharingLinks: nonisolated Decodable, Sendable {
    let total: Int?
    let offset: Int?
    let links: [SharingLink]

    private enum CodingKeys: String, CodingKey {
        case total, offset, links
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        total = container.flexInt(.total)
        offset = container.flexInt(.offset)
        links = try container.decode([SharingLink].self, forKey: .links)
    }
}

struct FileStationCreatedShareLinks: nonisolated Decodable, Sendable {
    let links: [FileStationCreatedShareLink]
}

struct FileStationCreatedShareLink: nonisolated Decodable, Sendable {
    let id: String?
    let url: String?
    let path: String?
    let qrCode: String?
    let errorCode: Int

    private enum CodingKeys: String, CodingKey {
        case id, url, path
        case qrCode = "qrcode"
        case errorCode = "error"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexString(.id)
        url = container.flexString(.url)
        path = container.flexString(.path)
        qrCode = container.flexString(.qrCode)
        // Not every NAS returns `error` when creation succeeds. Requiring it made the whole
        // response undecodable and failed a share that had in fact been created.
        errorCode = container.flexInt(.errorCode) ?? 0
    }
}

/// A share link: identifier, public URL, and path of the shared item
/// (`path` is only returned when listing, not on creation).
struct SharingLink: nonisolated Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let url: String
    let path: String?
    let name: String?
    let owner: String?
    let isFolder: Bool?
    let hasPassword: Bool?
    let availableDate: String?
    let expirationDate: String?
    let status: String?
    let qrCode: String?
    let creationError: Int?

    private enum CodingKeys: String, CodingKey {
        case id, url, path, name, status, qrcode
        case owner = "link_owner"
        case isFolder
        case hasPassword = "has_password"
        case availableDate = "date_available"
        case expirationDate = "date_expired"
        case creationError = "error"
    }

    nonisolated init(
        id: String,
        url: String,
        path: String?,
        name: String? = nil,
        owner: String? = nil,
        isFolder: Bool? = nil,
        hasPassword: Bool? = nil,
        availableDate: String? = nil,
        expirationDate: String? = nil,
        status: String? = nil,
        qrCode: String? = nil,
        creationError: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.path = path
        self.name = name
        self.owner = owner
        self.isFolder = isFolder
        self.hasPassword = hasPassword
        self.availableDate = availableDate
        self.expirationDate = expirationDate
        self.status = status
        self.qrCode = qrCode
        self.creationError = creationError
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.requiredFlexString(.id)
        url = try container.requiredFlexString(.url)
        path = container.flexString(.path)
        name = container.flexString(.name)
        owner = container.flexString(.owner)
        isFolder = container.flexBool(.isFolder)
        hasPassword = container.flexBool(.hasPassword)
        availableDate = container.flexString(.availableDate)
        expirationDate = container.flexString(.expirationDate)
        status = container.flexString(.status)
        qrCode = container.flexString(.qrcode)
        creationError = container.flexInt(.creationError)
    }

    /// What names the link on screen: DSM only fills `name` for some links, and a link with
    /// neither name nor path is still identified by the URL it hands out.
    var displayName: String { name ?? path ?? url }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableName: String { displayName }
    var sortableOwner: String { owner ?? "" }
    var sortableStatus: String { status ?? "" }
    var sortableAvailableDate: String { availableDate ?? "" }
    var sortableExpirationDate: String { expirationDate ?? "" }
    /// Sorted as text like `NASConnection.sortableTwoFactor`: `Bool` is not `Comparable`, and
    /// the column must be sortable like the others.
    var sortablePassword: String { hasPassword == true ? "1" : "0" }
}
