//
//  PackageInfo.swift
//  dsmaccess
//
//  Réponse de SYNO.Core.Package (method=list) : les paquets installés du Centre de paquets.
//  API NON documentée. Structure confirmée sur DSM 7.4 : id/name/version en haut niveau,
//  et l'état marche/arrêt imbriqué dans `additional.status` (« running », « stop »…).
//

import Foundation

struct PackageList: Decodable {
    let packages: [PackageInfo]?
}

struct PackageInfo: Decodable, Identifiable {
    let pkgId: String?
    let name: String?
    let version: String?
    let additional: Additional?

    /// Champs supplémentaires demandés via le paramètre `additional` de l'API.
    struct Additional: Decodable {
        let status: String?
        let installType: String?

        enum CodingKeys: String, CodingKey {
            case status
            case installType = "install_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case pkgId = "id"
        case name, version, additional
    }

    var id: String { pkgId ?? name ?? version ?? "?" }

    /// Nom affiché : le nom fourni, sinon l'identifiant.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return pkgId ?? String(localized: "Paquet inconnu")
    }

    /// État traduit (marche / arrêt).
    var statusText: String {
        switch additional?.status?.lowercased() {
        case "running", "start", "started": return String(localized: "En cours")
        case "stop", "stopped", "stopping": return String(localized: "Arrêté")
        case .some(let value) where !value.isEmpty: return value
        default: return "—"
        }
    }
}
