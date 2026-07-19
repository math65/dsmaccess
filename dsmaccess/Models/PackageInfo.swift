//
//  PackageInfo.swift
//  dsmaccess
//
//  Réponse de SYNO.Core.Package (method=list) : les paquets installés du Centre de paquets.
//  API NON documentée. Structure confirmée sur DSM 7.4 : id/name/version en haut niveau,
//  et l'état marche/arrêt imbriqué dans `additional.status` (« running », « stop »…).
//

import Foundation

struct PackageList: nonisolated Decodable, Sendable {
    let packages: [PackageInfo]?
}

/// Réponse du catalogue du Centre de paquets.
struct ServerPackageList: nonisolated Decodable, Sendable {
    let packages: [ServerPackage]?
}

struct ServerPackage: nonisolated Decodable, Sendable {
    let id: String?
    let version: String?
    let link: String?
    let md5: String?
    let size: Int?
    let beta: Bool?
    let source: String?
    let type: Int?

    private enum CodingKeys: String, CodingKey {
        case id, version, link, md5, size, beta, source, type
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexString(.id)
        version = container.flexString(.version)
        link = container.flexString(.link)
        md5 = container.flexString(.md5)
        size = container.flexInt(.size)
        beta = container.flexBool(.beta)
        source = container.flexString(.source)
        type = container.flexInt(.type)
    }
}

struct PackageInfo: nonisolated Decodable, Identifiable, Sendable {
    let pkgId: String
    let name: String?
    let version: String?
    let additional: Additional?

    /// Champs supplémentaires demandés via le paramètre `additional` de l'API.
    struct Additional: nonisolated Decodable, Sendable {
        let status: String?
        let installType: String?
        /// Le paquet peut-il être démarré/arrêté ? (absent pour les paquets non pilotables).
        let startable: Bool?
        /// Le paquet est-il désinstallable depuis l'UI ? (faux pour certains paquets système).
        let ctlUninstall: Bool?
        /// Le paquet propose-t-il des options de désinstallation custom dans DSM ?
        let isUninstallPages: Bool?

        enum CodingKeys: String, CodingKey {
            case status
            case installType = "install_type"
            case startable
            case ctlUninstall = "ctl_uninstall"
            case isUninstallPages = "is_uninstall_pages"
        }
    }

    enum CodingKeys: String, CodingKey {
        case pkgId = "id"
        case name, version, additional
    }

    var id: String { pkgId }

    /// Nom affiché : le nom fourni, sinon l'identifiant.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return pkgId
    }

    /// État traduit (marche / arrêt).
    var statusText: String {
        let status = additional?.status?.lowercased()
        switch status {
        case "running", "start", "started": return String(localized: "En cours")
        case "stop", "stopped", "stopping": return String(localized: "Arrêté")
        case .some(let value) where Self.requiresAttention(value):
            return String(localized: "Réparation requise")
        case .some(let value) where !value.isEmpty:
            return String(localized: "État DSM : \(value)")
        default: return "—"
        }
    }

    /// Vrai si le paquet tourne actuellement (même logique d'état que `statusText`).
    var isRunning: Bool {
        switch additional?.status?.lowercased() {
        case "running", "start", "started": return true
        default: return false
        }
    }

    var isStopped: Bool {
        switch additional?.status?.lowercased() {
        case "stop", "stopped", "stopping": true
        default: false
        }
    }

    var requiresAttention: Bool {
        guard let status = additional?.status?.lowercased() else { return false }
        return Self.requiresAttention(status)
    }

    private static func requiresAttention(_ status: String) -> Bool {
        ["repair", "repairing", "broken", "error", "corrupt", "corrupted"].contains(status)
            || status.hasPrefix("repair_")
            || status.hasPrefix("broken_")
            || status.hasPrefix("error_")
            || status.hasPrefix("corrupt_")
    }

    /// Vrai si le paquet peut être démarré/arrêté (certains paquets système ne le sont pas).
    var canStartStop: Bool { additional?.startable == true }

    /// Vrai si le paquet peut être désinstallé depuis l'app (certains paquets système non).
    var canUninstall: Bool { additional?.ctlUninstall == true }

    /// Vrai si le paquet propose des options de désinstallation dans DSM (non exposées ici).
    var hasUninstallOptions: Bool { additional?.isUninstallPages == true }
}
