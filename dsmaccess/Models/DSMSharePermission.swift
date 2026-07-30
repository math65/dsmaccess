//
//  DSMSharePermission.swift
//  dsmaccess
//
//  Droits d'un compte sur les dossiers partagés (SYNO.Core.Share.Permission).
//

import Foundation

/// Ce à quoi des droits sont accordés. DSM lit les deux cas par des méthodes distinctes mais
/// les écrit par la même, en distinguant l'un de l'autre par `user_group_type`.
enum DSMPermissionHolder: Sendable, Hashable, Identifiable {
    case user(String)
    case group(String)

    var name: String {
        switch self {
        case .user(let name), .group(let name): return name
        }
    }

    var id: String { apiType + ":" + name }

    var apiType: String {
        switch self {
        case .user: return "local_user"
        case .group: return "local_group"
        }
    }

    var listMethod: String {
        switch self {
        case .user: return "list_by_user"
        case .group: return "list_by_group"
        }
    }

    /// SYNO.Core.AppPriv nomme les mêmes entités autrement que SYNO.Core.Share.Permission.
    var entityType: String {
        switch self {
        case .user: return "user"
        case .group: return "group"
        }
    }

    /// Un groupe n'hérite de rien : DSM omet le droit hérité dans sa réponse, et l'écran n'a
    /// donc ni colonne d'héritage ni choix « hériter ».
    var inheritsFromGroups: Bool {
        if case .user = self { return true }
        return false
    }
}

/// Niveau d'accès à un dossier partagé, dans l'ordre où DSM présente ses colonnes.
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

    /// Rang de la règle de conflit affichée par DSM : NA > RW > RO.
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
    /// Droit hérité des groupes du compte. DSM répond « - » quand il n'y en a aucun.
    let inherited: DSMSharePermissionLevel?
    /// Droit propre au compte. `nil` quand aucune case n'est cochée : seul l'héritage compte.
    var granted: DSMSharePermissionLevel?
    /// DSM signale ici les permissions détaillées posées dans File Station, sans les décrire.
    let isCustom: Bool

    var id: String { name }

    /// Droit réellement appliqué, par la règle que DSM affiche sous sa grille : NA > RW > RO.
    /// Sans droit propre ni droit hérité, le compte n'a pas accès au dossier.
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

struct DSMSharePermissionList: nonisolated Decodable, Sendable {
    let shares: [DSMSharePermission]

    enum CodingKeys: String, CodingKey { case shares }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        shares = try values.decodeIfPresent([DSMSharePermission].self, forKey: .shares) ?? []
    }
}
