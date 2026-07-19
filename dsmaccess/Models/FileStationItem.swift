//
//  FileStationItem.swift
//  dsmaccess
//
//  Un élément (dossier ou fichier) renvoyé par SYNO.FileStation.List, que ce soit
//  un dossier partagé racine (method=list_share) ou le contenu d'un dossier (method=list).
//

import Foundation

/// Dossier ou fichier tel que décrit par File Station.
struct FileStationItem: nonisolated Decodable, Equatable, Identifiable, Sendable {
    /// Nom affiché (ex. « photo », « vacances.jpg »).
    let name: String
    /// Chemin absolu côté NAS (ex. « /photo/vacances.jpg ») — sert de clé de navigation.
    let path: String
    /// Vrai si c'est un dossier (donc dépliable), faux si c'est un fichier.
    let isdir: Bool
    /// Métadonnées optionnelles (taille, dates) demandées via le paramètre `additional`.
    let additional: Additional?
    /// Contenu renvoyé par `goto_path`, lorsqu'il est demandé.
    let children: FileStationChildren?

    var id: String { path }

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
        /// Taille en octets (fichiers uniquement).
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
        /// Date de dernière modification, en secondes depuis l'époque Unix.
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
    /// Ligne secondaire d'un fichier : « 2,3 Mo · 12 mars 2024 » (nil pour un dossier).
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

    /// Libellé complet lu par VoiceOver : « photo, dossier » ou « a.jpg, fichier, 2,3 Mo · 12 mars 2024 ».
    var accessibilityLabel: String {
        let kind = isdir ? String(localized: "dossier") : String(localized: "fichier")
        var label = "\(name), \(kind)"
        if let detail = detailText {
            label += ", \(detail)"
        }
        return label
    }
}

extension Array where Element == FileStationItem {
    /// Tri d'affichage : dossiers avant fichiers, puis par nom respectueux de la locale.
    func sortedForBrowsing() -> [FileStationItem] {
        sorted { lhs, rhs in
            if lhs.isdir != rhs.isdir { return lhs.isdir && !rhs.isdir }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// Charge utile de `method=list_share` : les dossiers partagés à la racine.
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

/// Charge utile de `method=list` : le contenu d'un dossier.
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

/// Réponse de `SYNO.FileStation.CopyMove` `method=start` : l'identifiant de tâche à suivre.
struct CopyMoveTask: nonisolated Decodable, Sendable {
    let taskid: String
}

struct FileOperationTask: nonisolated Decodable, Sendable {
    let taskid: String
}

/// Réponse de `SYNO.FileStation.Sharing` `method=create` : les liens de partage créés.
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
        errorCode = try container.requiredFlexInt(.errorCode)
    }
}

/// Un lien de partage : identifiant, URL publique, et chemin de l'élément partagé
/// (`path` n'est renvoyé qu'au listing, pas à la création).
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
}
