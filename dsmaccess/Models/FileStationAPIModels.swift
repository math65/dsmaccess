//
//  FileStationAPIModels.swift
//  dsmaccess
//
//  Options et résultats des API publiques de File Station.
//

import Foundation

struct FileStationPage<Element: Sendable>: Sendable {
    let total: Int
    let offset: Int
    let elements: [Element]
}

extension FileStationPage: Equatable where Element: Equatable {}

enum FileStationSortDirection: String, CaseIterable, Sendable {
    case ascending = "asc"
    case descending = "desc"
}

enum FileStationItemType: String, CaseIterable, Sendable {
    case all
    case file
    case directory = "dir"
}

enum FileStationListSort: String, CaseIterable, Sendable {
    case name
    case size
    case user
    case group
    case modifiedTime = "mtime"
    case accessedTime = "atime"
    case changedTime = "ctime"
    case createdTime = "crtime"
    case posix
    case type
}

struct FileStationListOptions: Equatable, Sendable {
    var offset: Int
    var limit: Int
    var sortBy: FileStationListSort
    var sortDirection: FileStationSortDirection
    var pattern: String?
    var itemType: FileStationItemType
    var goToPath: String?
    var onlyWritable: Bool

    nonisolated init(
        offset: Int = 0,
        limit: Int = 0,
        sortBy: FileStationListSort = .name,
        sortDirection: FileStationSortDirection = .ascending,
        pattern: String? = nil,
        itemType: FileStationItemType = .all,
        goToPath: String? = nil,
        onlyWritable: Bool = false
    ) {
        self.offset = offset
        self.limit = limit
        self.sortBy = sortBy
        self.sortDirection = sortDirection
        self.pattern = pattern
        self.itemType = itemType
        self.goToPath = goToPath
        self.onlyWritable = onlyWritable
    }
}

struct FileStationSearchCriteria: Equatable, Sendable {
    var folderPaths: [String]
    var recursive: Bool
    var pattern: String?
    var extensions: String?
    var itemType: FileStationItemType
    var minimumSize: Int64?
    var maximumSize: Int64?
    var modifiedAfter: Date?
    var modifiedBefore: Date?
    var createdAfter: Date?
    var createdBefore: Date?
    var accessedAfter: Date?
    var accessedBefore: Date?
    var owner: String?
    var group: String?

    nonisolated init(
        folderPaths: [String],
        recursive: Bool = true,
        pattern: String? = nil,
        extensions: String? = nil,
        itemType: FileStationItemType = .all,
        minimumSize: Int64? = nil,
        maximumSize: Int64? = nil,
        modifiedAfter: Date? = nil,
        modifiedBefore: Date? = nil,
        createdAfter: Date? = nil,
        createdBefore: Date? = nil,
        accessedAfter: Date? = nil,
        accessedBefore: Date? = nil,
        owner: String? = nil,
        group: String? = nil
    ) {
        self.folderPaths = folderPaths
        self.recursive = recursive
        self.pattern = pattern
        self.extensions = extensions
        self.itemType = itemType
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.accessedAfter = accessedAfter
        self.accessedBefore = accessedBefore
        self.owner = owner
        self.group = group
    }
}

struct FileStationSearchResultOptions: Equatable, Sendable {
    var offset: Int
    var limit: Int
    var sortBy: FileStationListSort
    var sortDirection: FileStationSortDirection
    var pattern: String?
    var itemType: FileStationItemType

    nonisolated init(
        offset: Int = 0,
        limit: Int = -1,
        sortBy: FileStationListSort = .name,
        sortDirection: FileStationSortDirection = .ascending,
        pattern: String? = nil,
        itemType: FileStationItemType = .all
    ) {
        self.offset = offset
        self.limit = limit
        self.sortBy = sortBy
        self.sortDirection = sortDirection
        self.pattern = pattern
        self.itemType = itemType
    }
}

struct FileStationSearchProgress: Equatable, Sendable {
    let taskID: String
    let isFinished: Bool
    let total: Int
    let files: [FileStationItem]
}

enum FileStationVirtualFolderType: String, CaseIterable, Identifiable, Sendable {
    case nfs
    case cifs
    case iso

    var id: Self { self }
}

struct FileStationVirtualFolders: nonisolated Decodable, Sendable {
    let total: Int
    let offset: Int
    let folders: [FileStationItem]

    private enum CodingKeys: String, CodingKey {
        case total, offset, folders
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folders = try container.decode([FileStationItem].self, forKey: .folders)
        total = container.flexInt(.total) ?? folders.count
        offset = container.flexInt(.offset) ?? 0
    }
}

enum FileStationFavoriteStatus: String, CaseIterable, Sendable {
    case all
    case valid
    case broken
}

enum FileStationThumbnailSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large
    case original
}

enum FileStationThumbnailRotation: Int, CaseIterable, Sendable {
    case none = 0
    case clockwise90 = 1
    case clockwise180 = 2
    case clockwise270 = 3
    case clockwise360 = 4
}

struct FileStationUploadOptions: Equatable, Sendable {
    var conflictPolicy: FileConflictPolicy
    var createParentFolders: Bool
    var modificationDate: Date?
    var creationDate: Date?
    var accessDate: Date?

    nonisolated init(
        conflictPolicy: FileConflictPolicy = .ask,
        createParentFolders: Bool = true,
        modificationDate: Date? = nil,
        creationDate: Date? = nil,
        accessDate: Date? = nil
    ) {
        self.conflictPolicy = conflictPolicy
        self.createParentFolders = createParentFolders
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.accessDate = accessDate
    }
}

struct FileStationFolderCreation: Equatable, Sendable {
    let parentPath: String
    let name: String
}

struct FileStationRenameChange: Equatable, Sendable {
    let path: String
    let name: String
}

enum FileStationSharingSort: String, CaseIterable, Sendable {
    case id
    case name
    case isFolder
    case path
    case expirationDate = "date_expired"
    case availableDate = "date_available"
    case status
    case hasPassword = "has_password"
    case url
    case owner = "link_owner"
}

struct FileStationSharingListOptions: Equatable, Sendable {
    var offset: Int
    var limit: Int
    var sortBy: FileStationSharingSort?
    var sortDirection: FileStationSortDirection
    var forceRefresh: Bool

    nonisolated init(
        offset: Int = 0,
        limit: Int = 0,
        sortBy: FileStationSharingSort? = nil,
        sortDirection: FileStationSortDirection = .ascending,
        forceRefresh: Bool = false
    ) {
        self.offset = offset
        self.limit = limit
        self.sortBy = sortBy
        self.sortDirection = sortDirection
        self.forceRefresh = forceRefresh
    }
}

struct FileStationShareLinkCreation: Equatable, Sendable {
    var paths: [String]
    var password: String?
    var expirationDate: String?
    var availableDate: String?

    nonisolated init(
        paths: [String],
        password: String? = nil,
        expirationDate: String? = nil,
        availableDate: String? = nil
    ) {
        self.paths = paths
        self.password = password
        self.expirationDate = expirationDate
        self.availableDate = availableDate
    }
}

struct FileStationShareLinkChanges: Equatable, Sendable {
    var password: String?
    var expirationDate: String?
    var availableDate: String?

    nonisolated init(
        password: String? = nil,
        expirationDate: String? = nil,
        availableDate: String? = nil
    ) {
        self.password = password
        self.expirationDate = expirationDate
        self.availableDate = availableDate
    }
}

enum FileStationCompressionLevel: String, CaseIterable, Sendable {
    case moderate
    case store
    case fastest
    case best
}

enum FileStationCompressionMode: String, CaseIterable, Sendable {
    case add
    case update
    case refreshen
    case synchronize
}

enum FileStationArchiveFormat: String, CaseIterable, Sendable {
    case zip
    case sevenZip = "7z"
}

struct FileStationCompressionOptions: Equatable, Sendable {
    var level: FileStationCompressionLevel
    var mode: FileStationCompressionMode
    var format: FileStationArchiveFormat
    var password: String?

    nonisolated init(
        level: FileStationCompressionLevel = .moderate,
        mode: FileStationCompressionMode = .add,
        format: FileStationArchiveFormat = .zip,
        password: String? = nil
    ) {
        self.level = level
        self.mode = mode
        self.format = format
        self.password = password
    }
}

enum FileStationArchiveCodepage: String, CaseIterable, Identifiable, Sendable {
    case english = "enu"
    case traditionalChinese = "cht"
    case simplifiedChinese = "chs"
    case korean = "krn"
    case german = "ger"
    case french = "fre"
    case italian = "ita"
    case spanish = "spn"
    case japanese = "jpn"
    case danish = "dan"
    case norwegian = "nor"
    case swedish = "sve"
    case dutch = "nld"
    case russian = "rus"
    case polish = "plk"
    case brazilianPortuguese = "ptb"
    case portuguese = "ptg"
    case hungarian = "hun"
    case turkish = "trk"
    case czech = "csy"

    var id: Self { self }
}

struct FileStationExtractionOptions: Equatable, Sendable {
    var conflictPolicy: FileConflictPolicy
    var keepsDirectoryStructure: Bool
    var createsSubfolder: Bool
    var codepage: FileStationArchiveCodepage?
    var password: String?
    var itemIDs: [Int]

    nonisolated init(
        conflictPolicy: FileConflictPolicy = .skip,
        keepsDirectoryStructure: Bool = true,
        createsSubfolder: Bool = true,
        codepage: FileStationArchiveCodepage? = nil,
        password: String? = nil,
        itemIDs: [Int] = []
    ) {
        self.conflictPolicy = conflictPolicy
        self.keepsDirectoryStructure = keepsDirectoryStructure
        self.createsSubfolder = createsSubfolder
        self.codepage = codepage
        self.password = password
        self.itemIDs = itemIDs
    }
}

enum FileStationArchiveSort: String, CaseIterable, Sendable {
    case name
    case size
    case packedSize = "pack_size"
    case modifiedTime = "mtime"
}

struct FileStationArchiveListOptions: Equatable, Sendable {
    var offset: Int
    var limit: Int
    var sortBy: FileStationArchiveSort
    var sortDirection: FileStationSortDirection
    var codepage: FileStationArchiveCodepage?
    var password: String?
    var parentItemID: Int?

    nonisolated init(
        offset: Int = 0,
        limit: Int = -1,
        sortBy: FileStationArchiveSort = .name,
        sortDirection: FileStationSortDirection = .ascending,
        codepage: FileStationArchiveCodepage? = nil,
        password: String? = nil,
        parentItemID: Int? = nil
    ) {
        self.offset = offset
        self.limit = limit
        self.sortBy = sortBy
        self.sortDirection = sortDirection
        self.codepage = codepage
        self.password = password
        self.parentItemID = parentItemID
    }
}

struct FileStationArchiveItems: nonisolated Decodable, Sendable {
    let total: Int
    let items: [FileStationArchiveItem]

    private enum CodingKeys: String, CodingKey {
        case total, items
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([FileStationArchiveItem].self, forKey: .items)
        total = container.flexInt(.total) ?? items.count
    }
}

struct FileStationArchiveItem: nonisolated Decodable, Equatable, Identifiable, Sendable {
    let itemID: Int
    let name: String
    let size: Int64
    let packedSize: Int64
    let modificationTime: String
    let path: String
    let isDirectory: Bool

    var id: Int { itemID }

    private enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case legacyItemID = "itemid"
        case name, size, path
        case packedSize = "pack_size"
        case modificationTime = "mtime"
        case isDirectory = "is_dir"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let itemID = container.flexInt(.itemID) ?? container.flexInt(.legacyItemID),
              let size = container.flexInt64(.size),
              let packedSize = container.flexInt64(.packedSize) else {
            throw DecodingError.dataCorruptedError(
                forKey: .itemID,
                in: container,
                debugDescription: "Archive item identifiers and sizes are required."
            )
        }
        self.itemID = itemID
        name = try container.requiredFlexString(.name)
        self.size = size
        self.packedSize = packedSize
        modificationTime = try container.requiredFlexString(.modificationTime)
        path = try container.requiredFlexString(.path)
        isDirectory = try container.requiredFlexBool(.isDirectory)
    }
}

enum FileStationBackgroundTaskSort: String, CaseIterable, Sendable {
    case creationTime = "crtime"
    case finished
}

struct FileStationBackgroundTaskListOptions: Equatable, Sendable {
    var offset: Int
    var limit: Int
    var sortBy: FileStationBackgroundTaskSort
    var sortDirection: FileStationSortDirection
    var apiKinds: [FileOperationKind]

    nonisolated init(
        offset: Int = 0,
        limit: Int = 0,
        sortBy: FileStationBackgroundTaskSort = .creationTime,
        sortDirection: FileStationSortDirection = .descending,
        apiKinds: [FileOperationKind] = []
    ) {
        self.offset = offset
        self.limit = limit
        self.sortBy = sortBy
        self.sortDirection = sortDirection
        self.apiKinds = apiKinds
    }
}
