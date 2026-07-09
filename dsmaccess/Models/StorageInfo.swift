//
//  StorageInfo.swift
//  dsmaccess
//
//  Réponse de SYNO.Storage.CGI.Storage (method=load_info), l'API du Gestionnaire de stockage DSM.
//  API NON documentée : structure calée sur des réponses réelles (les tailles sont des chaînes
//  d'octets à convertir). Champs optionnels par prudence.
//

import Foundation

struct StorageInfo: Decodable {
    let disks: [Disk]?
    let volumes: [Volume]?
}

/// Un disque physique.
struct Disk: Decodable, Identifiable {
    let id: String
    let name: String?
    let model: String?
    let diskType: String?      // "SATA", "SSD"…
    let sizeTotal: String?     // octets en chaîne
    let temp: Int?             // °C
    let status: String?
    let smartStatus: String?
    let order: Int?            // ordre d'affichage / de baie
    let numId: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, model, temp, status, diskType, order
        case numId = "num_id"
        case sizeTotal = "size_total"
        case smartStatus = "smart_status"
    }

    /// Clé de tri par baie (order → num_id → id naturel).
    var sortOrder: Int { order ?? numId ?? Int.max }
}

/// Un volume logique.
struct Volume: Decodable, Identifiable {
    let id: String
    let desc: String?          // ex. « Located on Storage Pool 1, SHR »
    let status: String?
    let fsType: String?        // "btrfs", "ext4"…
    let size: Size?

    struct Size: Decodable {
        let total: String?     // octets en chaîne
        let used: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, desc, status, size
        case fsType = "fs_type"
    }
}

// MARK: - Affichage / VoiceOver

/// Traduit un statut DSM brut en libellé localisé.
func localizedStorageStatus(_ raw: String?) -> String {
    switch raw?.lowercased() {
    case "normal": return String(localized: "Normal")
    case "degrade", "degraded": return String(localized: "Dégradé")
    case "crashed", "critical": return String(localized: "Critique")
    case .some(let value) where !value.isEmpty: return value
    default: return "—"
    }
}

extension Disk {
    var displayName: String {
        [name, model?.trimmingCharacters(in: .whitespaces)]
            .compactMap { $0 }.filter { !$0.isEmpty }
            .joined(separator: " — ")
            .ifEmpty(id)
    }
    var temperatureText: String? {
        guard let temp else { return nil }
        return String(localized: "\(temp) °C")
    }
    var healthText: String { localizedStorageStatus(smartStatus ?? status) }
    var sizeText: String? {
        sizeTotal.flatMap { Int64($0) }?.formatted(.byteCount(style: .file))
    }
}

extension Volume {
    var displayName: String { (desc?.isEmpty == false ? desc! : id) }
    var totalBytes: Int64? { size?.total.flatMap { Int64($0) } }
    var usedBytes: Int64? { size?.used.flatMap { Int64($0) } }
    var usagePercent: Int? {
        guard let total = totalBytes, total > 0, let used = usedBytes else { return nil }
        return Int((Double(used) / Double(total) * 100).rounded())
    }
    var spaceText: String? {
        guard let total = totalBytes, let used = usedBytes else { return nil }
        return String(localized: "\(used.formatted(.byteCount(style: .file))) utilisés sur \(total.formatted(.byteCount(style: .file)))")
    }
    var statusText: String { localizedStorageStatus(status) }
    var filesystemText: String { fsType?.uppercased() ?? "—" }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
