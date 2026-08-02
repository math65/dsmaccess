//
//  ShareInfo.swift
//  dsmaccess
//
//  NAS shared folders through SYNO.Core.Share. UNDOCUMENTED API: structure aligned with
//  Synology's open-source code (synology-csi). Fields optional out of caution.
//

import Foundation

/// Payload of `SYNO.Core.Share` `method=list`.
struct ShareList: nonisolated Decodable, Sendable {
    let shares: [SharedFolder]?
    let total: Int?
}

/// A shared folder.
struct SharedFolder: nonisolated Decodable, Identifiable, Sendable {
    let name: String
    let volPath: String?
    let desc: String?
    let uuid: String?
    let recyclebin: Bool?
    let shareQuota: Int?
    let externalDeviceType: String?

    enum CodingKeys: String, CodingKey {
        case name, desc, uuid, recyclebin
        case volPath = "vol_path"
        case shareQuota = "share_quota"
        case externalDeviceType = "external_dev_type"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        volPath = values.flexString(.volPath)
        desc = values.flexString(.desc)
        uuid = values.flexString(.uuid)
        recyclebin = values.flexBool(.recyclebin)
        shareQuota = values.flexInt(.shareQuota)
        externalDeviceType = values.flexString(.externalDeviceType)
    }

    var id: String { uuid ?? name }
}

/// `shareinfo` object sent to `SYNO.Core.Share` `create` (serialized as JSON in the parameter).
/// Fields aligned with the official Synology client (synology-csi); `encryption` as an Int (0/1).
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

// MARK: - Display / VoiceOver

/// "/volume1" → "Volume 1" for display; returns the raw path otherwise.
func volumeLabel(for path: String) -> String {
    if path.hasPrefix("/volume"), let n = Int(path.dropFirst("/volume".count)) {
        return String(localized: "common.label.volume_number", defaultValue: "Volume \(n)")
    }
    return path
}

extension SharedFolder {
    var displayName: String { name }

    /// Readable name of the volume hosting the share ("Volume 1").
    var volumeText: String? {
        guard let path = volPath, !path.isEmpty else { return nil }
        return volumeLabel(for: path)
    }

    /// DSM omits the flag rather than sending false on shares it has never been set on, so an
    /// absent value is reported as such instead of being read as a disabled recycle bin.
    var recycleBinDescription: String {
        guard let recyclebin else { return "—" }
        return recyclebin
            ? String(localized: "common.answer.yes")
            : String(localized: "common.answer.no")
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableName: String { displayName }
    var sortableVolume: String { volumeText ?? "" }
    var sortableDescription: String { desc ?? "" }
    /// Sorted as text like `NASConnection.sortableTwoFactor`: `Bool` is not `Comparable`.
    var sortableRecycleBin: String { recyclebin == true ? "1" : "0" }
}
