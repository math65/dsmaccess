//
//  ExternalStorageDevice.swift
//  dsmaccess
//
//  USB and eSATA storage reported by SYNO.Core.ExternalDevice.Storage.
//

import Foundation

/// A partition of an external device. DSM mounts each one as its own shared folder.
///
/// While the device is being formatted it still reports its partitions, but with an empty
/// `filesystem` and an empty `share_name`: both are therefore optional here rather than
/// carrying a meaningless empty string into the interface.
nonisolated struct ExternalStoragePartition: Identifiable, Sendable, Decodable, Equatable {
    let nameID: String
    let title: String?
    /// Name of the shared folder DSM mounts this partition on, as seen by File Station.
    /// ⚠️ Read it, never rebuild it: a single-partition device gives "usbshare1" while a
    /// multi-partition one gives "usbshare1-1".
    let shareName: String?
    let filesystem: String?
    let status: String
    let totalSizeMB: Int?
    let usedSizeMB: Int?

    var id: String { nameID }

    enum CodingKeys: String, CodingKey {
        case nameID = "name_id"
        case title = "partition_title"
        case shareName = "share_name"
        case filesystem
        case status
        case totalSizeMB = "total_size_mb"
        case usedSizeMB = "used_size_mb"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nameID = try container.decode(String.self, forKey: .nameID)
        title = try container.decodeIfPresent(String.self, forKey: .title)?.nilWhenEmpty
        shareName = try container.decodeIfPresent(String.self, forKey: .shareName)?.nilWhenEmpty
        filesystem = try container.decodeIfPresent(String.self, forKey: .filesystem)?.nilWhenEmpty
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        totalSizeMB = try container.decodeIfPresent(Int.self, forKey: .totalSizeMB)
        usedSizeMB = try container.decodeIfPresent(Int.self, forKey: .usedSizeMB)
    }

    var displayName: String {
        if let title, !title.isEmpty { return title }
        return nameID
    }
}

/// An external storage device, as returned by `list` with `additional: ["all"]`.
nonisolated struct ExternalStorageDevice: Identifiable, Sendable, Decodable, Equatable {
    let devID: String
    let title: String?
    let deviceType: String?
    let producer: String?
    let product: String?
    let status: String
    let totalSizeMB: Int?
    let isFormattable: Bool
    let partitions: [ExternalStoragePartition]
    /// Connection the device was listed from. DSM exposes USB and eSATA through two separate
    /// APIs with identical payloads, and the action calls must go back to the right one.
    var connection: ExternalStorageConnection = .usb

    var id: String { devID }

    enum CodingKeys: String, CodingKey {
        case devID = "dev_id"
        case title = "dev_title"
        case deviceType = "dev_type"
        case producer
        case product
        case status
        case totalSizeMB = "total_size_mb"
        case isFormattable = "formatable"
        case partitions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        devID = try container.decode(String.self, forKey: .devID)
        title = try container.decodeIfPresent(String.self, forKey: .title)?.nilWhenEmpty
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType)?.nilWhenEmpty
        producer = try container.decodeIfPresent(String.self, forKey: .producer)?.nilWhenEmpty
        product = try container.decodeIfPresent(String.self, forKey: .product)?.nilWhenEmpty
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        totalSizeMB = try container.decodeIfPresent(Int.self, forKey: .totalSizeMB)
        isFormattable = try container.decodeIfPresent(Bool.self, forKey: .isFormattable) ?? false
        partitions = try container.decodeIfPresent([ExternalStoragePartition].self, forKey: .partitions) ?? []
    }

    var displayName: String {
        if let title, !title.isEmpty { return title }
        return devID
    }

    /// True while DSM is formatting the device.
    /// ⚠️ `formating` with one "t" is Synology's spelling, measured on DSM 7.4. The progress
    /// field DSM also returns stays empty throughout, so this status is the only signal that
    /// the operation is running.
    var isFormatting: Bool {
        status.lowercased() == "formating"
    }

    /// Device state in words. Never rely on colour alone to carry it.
    var statusText: String {
        switch status.lowercased() {
        case "normal": String(localized: "external_devices.status.normal")
        case "formating": String(localized: "external_devices.status.formatting")
        case let value where value.isEmpty: String(localized: "common.status.unknown")
        case let value: String(localized: "external_devices.status.dsm_value", defaultValue: "DSM status: \(value)")
        }
    }
}

/// Which of the two DSM APIs a device came from.
nonisolated enum ExternalStorageConnection: String, CaseIterable, Sendable, Identifiable {
    case usb
    case esata

    var id: Self { self }

    /// Name of the DSM API serving this connection. The service turns it into a `DSMAPI`;
    /// endpoint construction does not belong to a model.
    var apiName: String {
        switch self {
        case .usb: "SYNO.Core.ExternalDevice.Storage.USB"
        case .esata: "SYNO.Core.ExternalDevice.Storage.eSATA"
        }
    }

    var title: String {
        switch self {
        case .usb: String(localized: "external_devices.connection.usb")
        case .esata: String(localized: "external_devices.connection.esata")
        }
    }
}

/// File systems DSM can format an external device with.
///
/// ⚠️ The raw values are the exact tokens DSM sends, measured by formatting a real key three
/// times: FAT32 travels as "fat", not "fat32".
nonisolated enum ExternalStorageFileSystem: String, CaseIterable, Identifiable, Sendable {
    case ext4
    case fat
    case exfat

    var id: Self { self }

    /// Synology's own product names, kept as DSM spells them.
    var title: String {
        switch self {
        case .ext4: "EXT4"
        case .fat: "FAT32"
        case .exfat: "EXFAT"
        }
    }

    var explanation: String {
        switch self {
        case .ext4: String(localized: "external_devices.filesystem.ext4.description")
        case .fat, .exfat: String(localized: "external_devices.filesystem.cross_platform.description")
        }
    }
}

/// The advanced settings shared by every external device.
nonisolated struct ExternalStorageSettings: Sendable, Decodable, Equatable {
    var forbidsUSB: Bool
    var allowsNonAdminEject: Bool
    var usesDelayedAllocation: Bool
    /// True when DSM needs a restart for the current settings to take effect.
    let needsReboot: Bool

    enum CodingKeys: String, CodingKey {
        case forbidsUSB = "forbid_usb"
        case allowsNonAdminEject = "non_admin_eject"
        case usesDelayedAllocation = "delalloc"
        case needsReboot = "needReboot"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        forbidsUSB = try container.decodeIfPresent(Bool.self, forKey: .forbidsUSB) ?? false
        allowsNonAdminEject = try container.decodeIfPresent(Bool.self, forKey: .allowsNonAdminEject) ?? false
        usesDelayedAllocation = try container.decodeIfPresent(Bool.self, forKey: .usesDelayedAllocation) ?? false
        needsReboot = try container.decodeIfPresent(Bool.self, forKey: .needsReboot) ?? false
    }
}

nonisolated struct ExternalStorageDeviceList: Sendable, Decodable {
    let devices: [ExternalStorageDevice]
}

private extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
