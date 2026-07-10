//
//  ShareInfo.swift
//  dsmaccess
//
//  Dossiers partagés du NAS via SYNO.Core.Share. API NON documentée : structure calée sur
//  le code open-source de Synology (synology-csi). Champs optionnels par prudence.
//

import Foundation

/// Charge utile de `SYNO.Core.Share` `method=list`.
struct ShareList: Decodable {
    let shares: [SharedFolder]?
    let total: Int?
}

/// Un dossier partagé.
struct SharedFolder: Decodable, Identifiable {
    let name: String?
    let volPath: String?
    let desc: String?
    let uuid: String?
    let recyclebin: Bool?
    let shareQuota: Int?

    enum CodingKeys: String, CodingKey {
        case name, desc, uuid, recyclebin
        case volPath = "vol_path"
        case shareQuota = "share_quota"
    }

    var id: String { uuid ?? name ?? UUID().uuidString }
}

/// Objet `shareinfo` envoyé à `SYNO.Core.Share` `create` (sérialisé en JSON dans le paramètre).
/// Champs calés sur le client officiel Synology (synology-csi) ; `encryption` en Int (0/1).
struct ShareCreateInfo: Encodable {
    let name: String
    let volPath: String
    let desc: String
    var enableRecycleBin = true
    var recycleBinAdminOnly = true
    var encryption = 0

    enum CodingKeys: String, CodingKey {
        case name, desc, encryption
        case volPath = "vol_path"
        case enableRecycleBin = "enable_recycle_bin"
        case recycleBinAdminOnly = "recycle_bin_admin_only"
    }
}

// MARK: - Affichage / VoiceOver

/// « /volume1 » → « Volume 1 » pour l'affichage ; renvoie le chemin brut sinon.
func volumeLabel(for path: String) -> String {
    if path.hasPrefix("/volume"), let n = Int(path.dropFirst("/volume".count)) {
        return String(localized: "Volume \(n)")
    }
    return path
}

extension SharedFolder {
    var displayName: String { name ?? "—" }

    /// Nom lisible du volume hébergeant le partage (« Volume 1 »).
    var volumeText: String? {
        guard let path = volPath, !path.isEmpty else { return nil }
        return volumeLabel(for: path)
    }

    /// Ligne secondaire : « Volume 1 · Sauvegardes Mac » (nil si rien à montrer).
    var subtitleText: String? {
        var parts: [String] = []
        if let vol = volumeText { parts.append(vol) }
        if let d = desc, !d.isEmpty { parts.append(d) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Libellé VoiceOver complet : « Sauvegardes, sur Volume 1, Sauvegardes Mac ».
    var accessibilityLabel: String {
        var label = displayName
        if let vol = volumeText { label += ", " + String(localized: "sur \(vol)") }
        if let d = desc, !d.isEmpty { label += ", \(d)" }
        return label
    }
}
