//
//  StorageInfo.swift
//  dsmaccess
//
//  Response of SYNO.Storage.CGI.Storage (method=load_info), the API behind DSM Storage Manager.
//  UNDOCUMENTED API: the structure is modelled on real responses (sizes are byte strings that
//  have to be converted). Fields are optional out of caution.
//

import Foundation

struct StorageInfo: nonisolated Decodable, Sendable {
    let disks: [Disk]?
    let volumes: [Volume]?
    let storagePools: [StoragePool]?
}

/// Size (bytes and inodes as strings) shared by volumes and pools.
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

/// A physical disk.
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
    // Extended health (the wear fields vary too much across DSM versions → left out for now).
    let unc: Int?                     // uncorrectable sectors
    let usedBy: String?               // pool it belongs to

    enum CodingKeys: String, CodingKey {
        case id, name, model, temp, status, diskType, order, unc
        case numId = "num_id"
        case sizeTotal = "size_total"
        case smartStatus = "smart_status"
        case usedBy = "used_by"
    }

    var sortOrder: Int { order ?? numId ?? Int.max }
}

/// A logical volume.
struct Volume: nonisolated Decodable, Identifiable, Sendable {
    let id: String
    let numId: Int?
    let desc: String?
    let status: String?
    let fsType: String?
    let size: ByteSize?
    let progress: Progress?
    /// Mount point, "/volume1". This is the form in which the performance alarm rules refer
    /// to a volume.
    let mountPath: String?

    struct Progress: nonisolated Decodable, Sendable {
        let percent: String?
        let step: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, desc, status, size, progress
        case numId = "num_id"
        case fsType = "fs_type"
        case mountPath = "vol_path"
    }
}

/// A storage pool and its RAID.
struct StoragePool: nonisolated Decodable, Identifiable, Sendable {
    let id: String
    let desc: String?
    let deviceType: String?          // "shr_with_2_disk_protect", "raid_5", "basic"…
    let status: String?
    let numId: Int?
    let disks: [String]?             // ids of the member disks
    let size: ByteSize?

    enum CodingKeys: String, CodingKey {
        case id, desc, status, disks, size
        case deviceType = "device_type"
        case numId = "num_id"
    }

    var sortOrder: Int { numId ?? Int.max }
}

// MARK: - Display / VoiceOver

/// Turns a raw DSM status into a localized label.
func localizedStorageStatus(_ raw: String?) -> String {
    switch raw?.lowercased() {
    case "normal": return String(localized: "storage.status.normal")
    case "degrade", "degraded": return String(localized: "storage.status.degraded")
    case "repairing", "rebuilding": return String(localized: "storage.status.rebuilding")
    case "expanding": return String(localized: "storage.status.expanding")
    case "crashed", "critical": return String(localized: "common.level.critical")
    case "attention", "warning": return String(localized: "storage.status.attention")
    case .some(let value) where !value.isEmpty: return value
    default: return "—"
    }
}

/// Formats as "X used of Y" from two byte strings.
func formattedSpace(usedBytes: String?, totalBytes: String?) -> String? {
    guard let used = usedBytes.flatMap({ Int64($0) }),
          let total = totalBytes.flatMap({ Int64($0) }),
          used >= 0, total >= 0 else { return nil }
    return String(localized: "storage.volume.used_of_total", defaultValue: "\(used.formatted(.byteCount(style: .file))) used of \(total.formatted(.byteCount(style: .file)))")
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
        return String(localized: "common.unit.celsius", defaultValue: "\(temp) °C")
    }
    var healthText: String { localizedStorageStatus(smartStatus ?? status) }
    var sizeText: String? {
        sizeTotal.flatMap { Int64($0) }?.formatted(.byteCount(style: .file))
    }
    /// Uncorrectable sectors (nil when there are none).
    var uncText: String? {
        guard let unc, unc > 0 else { return nil }
        return String(localized: "storage.disk.uncorrectable_sectors", defaultValue: "\(unc) uncorrectable sectors")
    }
}

extension Volume {
    var displayName: String { numId.map { String(localized: "common.label.volume_number", defaultValue: "Volume \($0)") } ?? id }
    var spaceText: String? { formattedSpace(usedBytes: size?.used, totalBytes: size?.total) }
    var usagePercentValue: Int? { usagePercent(usedBytes: size?.used, totalBytes: size?.total) }
    var statusText: String { localizedStorageStatus(status) }
    var filesystemText: String { fsType?.uppercased() ?? "—" }
    /// Progress of an operation under way ("Rebuilding 47 %"), otherwise nil.
    var operationText: String? {
        guard let step = progress?.step, step != "none",
              let pct = progress?.percent.flatMap({ Int($0) }),
              (0...100).contains(pct) else { return nil }
        return "\(localizedStorageStatus(step)) \(pct) %"
    }
    /// Percentage of inodes used (nil when unavailable).
    var inodePercent: Int? {
        guard let total = size?.totalInode.flatMap({ Int64($0) }), total > 0,
              let free = size?.freeInode.flatMap({ Int64($0) }),
              (0...total).contains(free) else { return nil }
        return Int((Double(total - free) / Double(total) * 100).rounded())
    }
}

extension StoragePool {
    var displayName: String { numId.map { String(localized: "storage.pool.name", defaultValue: "Storage pool \($0)") } ?? id }
    var statusText: String { localizedStorageStatus(status) }
    var raidTypeText: String {
        guard let type = deviceType, !type.isEmpty else { return "—" }
        if type.hasPrefix("shr") { return "SHR" }
        if type.hasPrefix("raid_") { return "RAID " + type.dropFirst("raid_".count).uppercased() }
        if type == "basic" { return String(localized: "storage.raid.basic") }
        return type
    }
    var diskCountText: String { String(localized: "storage.pool.disk_count", defaultValue: "\(disks?.count ?? 0) disks") }
    var sizeText: String? {
        size?.total.flatMap { Int64($0) }?.formatted(.byteCount(style: .file))
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
