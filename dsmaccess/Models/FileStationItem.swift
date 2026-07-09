//
//  FileStationItem.swift
//  dsmaccess
//
//  Un élément (dossier ou fichier) renvoyé par SYNO.FileStation.List, que ce soit
//  un dossier partagé racine (method=list_share) ou le contenu d'un dossier (method=list).
//

import Foundation

/// Dossier ou fichier tel que décrit par File Station.
struct FileStationItem: Decodable, Identifiable {
    /// Nom affiché (ex. « photo », « vacances.jpg »).
    let name: String
    /// Chemin absolu côté NAS (ex. « /photo/vacances.jpg ») — sert de clé de navigation.
    let path: String
    /// Vrai si c'est un dossier (donc dépliable), faux si c'est un fichier.
    let isdir: Bool
    /// Métadonnées optionnelles (taille, dates) demandées via le paramètre `additional`.
    let additional: Additional?

    var id: String { path }

    struct Additional: Decodable {
        /// Taille en octets (fichiers uniquement).
        let size: Int64?
        let time: TimeInfo?
    }

    struct TimeInfo: Decodable {
        /// Date de dernière modification, en secondes depuis l'époque Unix.
        let mtime: Int?
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
struct FileStationShares: Decodable {
    let shares: [FileStationItem]
}

/// Charge utile de `method=list` : le contenu d'un dossier.
struct FileStationFiles: Decodable {
    let files: [FileStationItem]
}
