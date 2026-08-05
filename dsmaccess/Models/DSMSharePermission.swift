//
//  DSMSharePermission.swift
//  dsmaccess
//
//  Rights of an account on shared folders (SYNO.Core.Share.Permission).
//

import Foundation

/// What rights are granted to. DSM reads both cases through distinct methods but writes them
/// through the same one, telling one from the other by `user_group_type`.
enum DSMPermissionHolder: Sendable, Hashable, Identifiable {
    case user(String)
    case group(String)

    var name: String {
        switch self {
        case .user(let name), .group(let name): return name
        }
    }

    var id: String { apiType + ":" + name }

    /// The holder without its name, for the reverse reading: which accounts reach one folder.
    enum Kind: String, Sendable, Hashable, CaseIterable, Identifiable {
        case user
        case group

        var id: String { rawValue }

        var apiType: String {
            switch self {
            case .user: return "local_user"
            case .group: return "local_group"
            }
        }

        var label: String {
            switch self {
            case .user: return String(localized: "permissions.accounts.users")
            case .group: return String(localized: "permissions.accounts.groups")
            }
        }
    }

    var kind: Kind {
        switch self {
        case .user: return .user
        case .group: return .group
        }
    }

    var apiType: String { kind.apiType }

    var listMethod: String {
        switch self {
        case .user: return "list_by_user"
        case .group: return "list_by_group"
        }
    }

    /// SYNO.Core.AppPriv names the same entities differently from SYNO.Core.Share.Permission.
    var entityType: String {
        switch self {
        case .user: return "user"
        case .group: return "group"
        }
    }

    /// A group inherits nothing: DSM omits the inherited right from its response, so the
    /// screen has neither an inheritance column nor an “inherit” choice.
    var inheritsFromGroups: Bool {
        if case .user = self { return true }
        return false
    }
}

/// Access level to a shared folder, in the order in which DSM presents its columns.
enum DSMSharePermissionLevel: String, Sendable, Hashable, CaseIterable, Identifiable {
    case noAccess
    case readWrite
    case readOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noAccess: return String(localized: "permissions.share.no_access")
        case .readWrite: return String(localized: "permissions.share.read_write")
        case .readOnly: return String(localized: "common.permission.read_only")
        }
    }

    /// Rank of the conflict rule displayed by DSM: NA > RW > RO.
    private var priority: Int {
        switch self {
        case .noAccess: return 3
        case .readWrite: return 2
        case .readOnly: return 1
        }
    }

    static func strongest(_ levels: DSMSharePermissionLevel?...) -> DSMSharePermissionLevel? {
        levels.compactMap { $0 }.max { $0.priority < $1.priority }
    }
}

struct DSMSharePermission: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let path: String?
    /// Right inherited from the account's groups. DSM answers “-” when there is none.
    let inherited: DSMSharePermissionLevel?
    /// Right specific to the account. `nil` when no box is checked: only inheritance counts.
    var granted: DSMSharePermissionLevel?
    /// DSM reports here the detailed permissions set in File Station, without describing them.
    let isCustom: Bool

    var id: String { name }

    /// Right actually applied, by the rule DSM displays under its grid: NA > RW > RO.
    /// With neither an own right nor an inherited one, the account has no access to the folder.
    var effective: DSMSharePermissionLevel {
        DSMSharePermissionLevel.strongest(granted, inherited) ?? .noAccess
    }

    enum CodingKeys: String, CodingKey {
        case name
        case path = "share_path"
        case inherit
        case isReadOnly = "is_readonly"
        case isWritable = "is_writable"
        case isDeny = "is_deny"
        case isCustom = "is_custom"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        path = values.flexString(.path)
        switch values.flexString(.inherit) {
        case "na": inherited = .noAccess
        case "rw": inherited = .readWrite
        case "ro": inherited = .readOnly
        default: inherited = nil
        }
        if values.flexBool(.isDeny) == true {
            granted = .noAccess
        } else if values.flexBool(.isWritable) == true {
            granted = .readWrite
        } else if values.flexBool(.isReadOnly) == true {
            granted = .readOnly
        } else {
            granted = nil
        }
        isCustom = values.flexBool(.isCustom) ?? false
    }

    init(
        name: String,
        path: String? = nil,
        inherited: DSMSharePermissionLevel? = nil,
        granted: DSMSharePermissionLevel? = nil,
        isCustom: Bool = false
    ) {
        self.name = name
        self.path = path
        self.inherited = inherited
        self.granted = granted
        self.isCustom = isCustom
    }
}

/// Answer of `SYNO.Core.Share.Permission` `list` with `action=enum`: the accounts reaching one
/// folder. Same rows as `DSMSharePermissionList`, under `items` instead of `shares`, and each
/// `name` is an account rather than a folder.
struct DSMShareAccountPermissionList: nonisolated Decodable, Sendable {
    let items: [DSMSharePermission]
    let total: Int?

    enum CodingKeys: String, CodingKey { case items, total }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = try values.decodeIfPresent([DSMSharePermission].self, forKey: .items) ?? []
        total = values.flexInt(.total)
    }
}

struct DSMSharePermissionList: nonisolated Decodable, Sendable {
    let shares: [DSMSharePermission]

    enum CodingKeys: String, CodingKey { case shares }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shares = try values.decodeIfPresent([DSMSharePermission].self, forKey: .shares) ?? []
    }
}
