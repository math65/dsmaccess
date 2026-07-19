//
//  FileStationItem.swift
//  dsmaccess
//
//  Un élément (dossier ou fichier) renvoyé par SYNO.FileStation.List, que ce soit
//  un dossier partagé racine (method=list_share) ou le contenu d'un dossier (method=list).
//

import Foundation

/// Dossier ou fichier tel que décrit par File Station.
struct FileStationItem: nonisolated Decodable, Identifiable, Sendable {
    /// Nom affiché (ex. « photo », « vacances.jpg »).
    let name: String
    /// Chemin absolu côté NAS (ex. « /photo/vacances.jpg ») — sert de clé de navigation.
    let path: String
    /// Vrai si c'est un dossier (donc dépliable), faux si c'est un fichier.
    let isdir: Bool
    /// Métadonnées optionnelles (taille, dates) demandées via le paramètre `additional`.
    let additional: Additional?

    var id: String { path }

    struct Additional: nonisolated Decodable, Sendable {
        /// Taille en octets (fichiers uniquement).
        let size: Int64?
        let time: TimeInfo?
        let owner: OwnerInfo?
        let permission: PermissionInfo?
        let type: String?
        let realPath: String?

        enum CodingKeys: String, CodingKey {
            case size, time, owner, type
            case permission = "perm"
            case realPath = "real_path"
        }
    }

    struct TimeInfo: nonisolated Decodable, Sendable {
        /// Date de dernière modification, en secondes depuis l'époque Unix.
        let mtime: Int?
        let atime: Int?
        let ctime: Int?
        let crtime: Int?
    }

    struct OwnerInfo: nonisolated Decodable, Sendable {
        let user: String?
        let group: String?
    }

    struct PermissionInfo: nonisolated Decodable, Sendable {
        let posix: Int?
        let acl: ACLInfo?
    }

    struct ACLInfo: nonisolated Decodable, Sendable {
        let read: Bool?
        let write: Bool?
        let delete: Bool?

        enum CodingKeys: String, CodingKey {
            case read, write
            case delete = "del"
        }
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
    let shares: [FileStationItem]
}

/// Charge utile de `method=list` : le contenu d'un dossier.
struct FileStationFiles: nonisolated Decodable, Sendable {
    let files: [FileStationItem]
}

struct FileStationSearchTask: nonisolated Decodable, Sendable {
    let taskid: String
}

struct FileStationSearchResults: nonisolated Decodable, Sendable {
    let files: [FileStationItem]
    let finished: Bool
}

struct FileStationFavorites: nonisolated Decodable, Sendable {
    let favorites: [FileStationFavorite]
}

struct FileStationFavorite: nonisolated Decodable, Identifiable, Sendable {
    let path: String
    let name: String
    let status: String?

    var id: String { path }
    var isAvailable: Bool { status != "broken" }
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
    let links: [SharingLink]
}

/// Un lien de partage : identifiant, URL publique, et chemin de l'élément partagé
/// (`path` n'est renvoyé qu'au listing, pas à la création).
struct SharingLink: nonisolated Decodable, Identifiable, Sendable {
    let id: String
    let url: String
    let path: String?
}
