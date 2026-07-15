//
//  StorageInfo.swift
//  dsmaccess
//
//  Réponse de SYNO.Storage.CGI.Storage (method=load_info), l'API du Gestionnaire de stockage DSM.
//  API NON documentée : structure calée sur des réponses réelles (les tailles sont des chaînes
//  d'octets à convertir). Champs optionnels par prudence.
//

import Foundation

struct StorageInfo: nonisolated Decodable, Sendable {
    let disks: [Disk]?
    let volumes: [Volume]?
    let storagePools: [StoragePool]?
}

/// Taille (octets et inodes en chaînes) partagée par volumes et pools.
struct ByteSize: nonisolated Decodable, Sendable {
    let total: String?
    let used: String?
    let totalInode: String?
    let freeInode: String?

    enum CodingKeys: String, CodingKey {
        case total, used
        case totalInode = "total_inode"
        case freeInode = "free_inode"
    }
}

/// Un disque physique.
struct Disk: nonisolated Decodable, Identifiable, Sendable {
    let id: String
    let name: String?
    let model: String?
    let diskType: String?
    let sizeTotal: String?
    let temp: Int?
    let status: String?
    let smartStatus: String?
    let order: Int?
    let numId: Int?
    // Santé étendue (les champs d'usure varient trop entre versions DSM → écartés pour l'instant).
    let unc: Int?                     // secteurs non corrigibles
    let usedBy: String?               // pool auquel il appartient

    enum CodingKeys: String, CodingKey {
        case id, name, model, temp, status, diskType, order, unc
        case numId = "num_id"
        case sizeTotal = "size_total"
        case smartStatus = "smart_status"
        case usedBy = "used_by"
    }

    var sortOrder: Int { order ?? numId ?? Int.max }
}

/// Un volume logique.
struct Volume: nonisolated Decodable, Identifiable, Sendable {
    let id: String
    let numId: Int?
    let desc: String?
    let status: String?
    let fsType: String?
    let size: ByteSize?
    let progress: Progress?

    struct Progress: nonisolated Decodable, Sendable {
        let percent: String?
        let step: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, desc, status, size, progress
        case numId = "num_id"
        case fsType = "fs_type"
    }
}

/// Un groupe de stockage (pool) et son RAID.
struct StoragePool: nonisolated Decodable, Identifiable, Sendable {
    let id: String
    let desc: String?
    let deviceType: String?          // "shr_with_2_disk_protect", "raid_5", "basic"…
    let status: String?
    let numId: Int?
    let disks: [String]?             // ids des disques membres
    let size: ByteSize?

    enum CodingKeys: String, CodingKey {
        case id, desc, status, disks, size
        case deviceType = "device_type"
        case numId = "num_id"
    }

    var sortOrder: Int { numId ?? Int.max }
}

// MARK: - Affichage / VoiceOver

/// Traduit un statut DSM brut en libellé localisé.
func localizedStorageStatus(_ raw: String?) -> String {
    switch raw?.lowercased() {
    case "normal": return String(localized: "Normal")
    case "degrade", "degraded": return String(localized: "Dégradé")
    case "repairing", "rebuilding": return String(localized: "Reconstruction")
    case "expanding": return String(localized: "Extension")
    case "crashed", "critical": return String(localized: "Critique")
    case "attention", "warning": return String(localized: "Attention")
    case .some(let value) where !value.isEmpty: return value
    default: return "—"
    }
}

/// Formate en « X utilisés sur Y » à partir de deux chaînes d'octets.
func formattedSpace(usedBytes: String?, totalBytes: String?) -> String? {
    guard let used = usedBytes.flatMap({ Int64($0) }),
          let total = totalBytes.flatMap({ Int64($0) }),
          used >= 0, total >= 0 else { return nil }
    return String(localized: "\(used.formatted(.byteCount(style: .file))) utilisés sur \(total.formatted(.byteCount(style: .file)))")
}

func usagePercent(usedBytes: String?, totalBytes: String?) -> Int? {
    guard let used = usedBytes.flatMap({ Int64($0) }),
          let total = totalBytes.flatMap({ Int64($0) }),
          total > 0, (0...total).contains(used) else { return nil }
    return Int((Double(used) / Double(total) * 100).rounded())
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
    /// Secteurs non corrigibles (nil si aucun).
    var uncText: String? {
        guard let unc, unc > 0 else { return nil }
        return String(localized: "\(unc) secteurs non corrigibles")
    }
}

extension Volume {
    var displayName: String { numId.map { String(localized: "Volume \($0)") } ?? id }
    var spaceText: String? { formattedSpace(usedBytes: size?.used, totalBytes: size?.total) }
    var usagePercentValue: Int? { usagePercent(usedBytes: size?.used, totalBytes: size?.total) }
    var statusText: String { localizedStorageStatus(status) }
    var filesystemText: String { fsType?.uppercased() ?? "—" }
    /// Progression d'une opération en cours (« Reconstruction 47 % »), sinon nil.
    var operationText: String? {
        guard let step = progress?.step, step != "none",
              let pct = progress?.percent.flatMap({ Int($0) }),
              (0...100).contains(pct) else { return nil }
        return "\(localizedStorageStatus(step)) \(pct) %"
    }
    /// Pourcentage d'inodes utilisés (nil si non disponible).
    var inodePercent: Int? {
        guard let total = size?.totalInode.flatMap({ Int64($0) }), total > 0,
              let free = size?.freeInode.flatMap({ Int64($0) }),
              (0...total).contains(free) else { return nil }
        return Int((Double(total - free) / Double(total) * 100).rounded())
    }
}

extension StoragePool {
    var displayName: String { numId.map { String(localized: "Groupe de stockage \($0)") } ?? id }
    var statusText: String { localizedStorageStatus(status) }
    var raidTypeText: String {
        guard let type = deviceType, !type.isEmpty else { return "—" }
        if type.hasPrefix("shr") { return "SHR" }
        if type.hasPrefix("raid_") { return "RAID " + type.dropFirst("raid_".count).uppercased() }
        if type == "basic" { return String(localized: "Basique") }
        return type
    }
    var diskCountText: String { String(localized: "\(disks?.count ?? 0) disques") }
    var sizeText: String? {
        size?.total.flatMap { Int64($0) }?.formatted(.byteCount(style: .file))
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
