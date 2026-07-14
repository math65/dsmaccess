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

/// Réponse de SYNO.Core.Package.Server (method=list) : le catalogue des paquets disponibles
/// (officiels et tiers-parti). On en retient l'identifiant, la version ET les métadonnées de
/// téléchargement (lien du .spk, checksum, taille) nécessaires pour appliquer une mise à jour.
struct ServerPackageList: Decodable {
    let packages: [ServerPackage]?
}

/// Une entrée du catalogue. Champs confirmés sur DSM 7.4 (cf. mémoire reference-flux-upgrade-paquet).
struct ServerPackage: Decodable {
    let id: String?
    let version: String?
    /// URL complète du fichier .spk à télécharger.
    let link: String?
    /// Somme de contrôle MD5 du .spk (passée à l'API d'installation).
    let md5: String?
    /// Taille du .spk en octets.
    let size: Int?
    /// Vrai si cette entrée du catalogue est une version bêta.
    let beta: Bool?
    /// Origine du paquet ("syno" pour le catalogue officiel Synology).
    let source: String?
    /// Type de paquet (0 = standard).
    let type: Int?
}

/// Métadonnées d'une mise à jour disponible, réunies depuis le catalogue : tout ce qu'il faut
/// pour la déclencher via l'appel « upgrade » (les paramètres exacts qu'envoie le Package Center web).
struct PackageUpdate {
    let id: String
    let version: String
    let link: String
    let md5: String
    let size: Int
    /// Paquet officiel Synology (source == "syno").
    let isSyno: Bool
    /// Version bêta au catalogue.
    let beta: Bool
    /// Type de paquet (0 = standard).
    let type: Int
}

/// Retour de SYNO.Core.Package.Installation `method=install` : le téléchargement est lancé,
/// identifié par un `taskid` (à re-passer aux étapes status/upgrade). API non documentée ;
/// on tolère `taskid` comme `task_id` selon les variantes DSM.
struct PackageInstallTask: Decodable {
    let taskid: String

    private enum CodingKeys: String, CodingKey {
        case taskid
        case taskIdSnake = "task_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .taskid) {
            taskid = value
        } else {
            taskid = try container.decode(String.self, forKey: .taskIdSnake)
        }
    }
}

/// Retour de SYNO.Core.Package.Installation `method=status` : avancement du téléchargement.
struct PackageInstallStatus: Decodable {
    let finished: Bool?
    let progress: Double?
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

    /// Vrai si le paquet tourne actuellement (même logique d'état que `statusText`).
    var isRunning: Bool {
        switch additional?.status?.lowercased() {
        case "running", "start", "started": return true
        default: return false
        }
    }

    /// Vrai si le paquet peut être démarré/arrêté (certains paquets système ne le sont pas).
    var canStartStop: Bool { additional?.startable == true }

    /// Vrai si le paquet peut être désinstallé depuis l'app (certains paquets système non).
    var canUninstall: Bool { additional?.ctlUninstall == true }

    /// Vrai si le paquet propose des options de désinstallation dans DSM (non exposées ici).
    var hasUninstallOptions: Bool { additional?.isUninstallPages == true }
}
