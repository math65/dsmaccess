//
//  ShareInfo.swift
//  dsmaccess
//
//  NAS shared folders through SYNO.Core.Share. UNDOCUMENTED API: the contract below was
//  measured on DSM 7.4 (DS920+) against the requests the web client itself sends.
//

import Foundation

/// Payload of `SYNO.Core.Share` `method=list`.
struct ShareList: nonisolated Decodable, Sendable {
    let shares: [SharedFolder]?
    let total: Int?
}

/// Encryption state DSM reports for a shared folder.
///
/// `encryption` is an Int, not a flag: a folder can be encrypted yet unmounted, in which case
/// its contents are unreachable until someone unlocks it with the key.
enum ShareEncryptionState: Int, Sendable, CaseIterable {
    case none = 0
    case locked = 1
    case mounted = 2

    var isEncrypted: Bool { self != .none }
}

/// A shared folder.
struct SharedFolder: nonisolated Decodable, Identifiable, Sendable {
    let name: String
    let volPath: String?
    let desc: String?
    let uuid: String?
    /// DSM only reports the recycle-bin keys when `recyclebin` is part of `additional`, and it
    /// omits them entirely on a folder whose recycle bin has never been switched on — measured
    /// against DSM's own edit screen, which shows the box unticked in exactly that case.
    let recycleBinEnabled: Bool?
    let recycleBinAdminOnly: Bool?
    let encryptionState: ShareEncryptionState
    /// Hidden from "My Network Places" (`additional=hidden`).
    let hidden: Bool?
    /// Hides sub-folders the user has no permission on (`additional=advance_setting`).
    let hidesUnreadableItems: Bool?
    /// Quota in megabytes, `0` meaning no quota. DSM reads it back as `quota_value` although
    /// it is written as `share_quota` — the two names are not interchangeable.
    let quotaMegabytes: Int?
    let compressionEnabled: Bool?
    /// Data checksum (copy-on-write). DSM only lets it be chosen when the folder is created.
    let checksumEnabled: Bool?
    let disablesListing: Bool?
    let disablesModification: Bool?
    let disablesDownload: Bool?
    let externalDeviceType: String?

    enum CodingKeys: String, CodingKey {
        case name, desc, uuid, hidden, encryption
        case volPath = "vol_path"
        case recycleBinEnabled = "enable_recycle_bin"
        case recycleBinAdminOnly = "recycle_bin_admin_only"
        case hidesUnreadableItems = "hide_unreadable"
        case quotaMegabytes = "quota_value"
        case compressionEnabled = "enable_share_compress"
        case checksumEnabled = "enable_share_cow"
        case disablesListing = "disable_list"
        case disablesModification = "disable_modify"
        case disablesDownload = "disable_download"
        case externalDeviceType = "external_dev_type"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        volPath = values.flexString(.volPath)
        desc = values.flexString(.desc)
        uuid = values.flexString(.uuid)
        recycleBinEnabled = values.flexBool(.recycleBinEnabled)
        recycleBinAdminOnly = values.flexBool(.recycleBinAdminOnly)
        encryptionState = values.flexInt(.encryption).flatMap(ShareEncryptionState.init(rawValue:)) ?? .none
        hidden = values.flexBool(.hidden)
        hidesUnreadableItems = values.flexBool(.hidesUnreadableItems)
        quotaMegabytes = values.flexInt(.quotaMegabytes)
        compressionEnabled = values.flexBool(.compressionEnabled)
        checksumEnabled = values.flexBool(.checksumEnabled)
        disablesListing = values.flexBool(.disablesListing)
        disablesModification = values.flexBool(.disablesModification)
        disablesDownload = values.flexBool(.disablesDownload)
        externalDeviceType = values.flexString(.externalDeviceType)
    }

    var id: String { uuid ?? name }
}

// MARK: - Creation

/// `shareinfo` object sent to `SYNO.Core.Share` `create`.
///
/// `encryption` is deliberately absent unless a key is supplied: DSM 7.4 answers **502** and
/// drops the request when `create` carries `encryption: false`, and rejects the integer `1`.
/// Encrypting on creation is the boolean `true` plus `enc_passwd`, which is what was measured
/// to work — the web client simply omits both fields when the folder is not encrypted.
struct SharedFolderCreation: nonisolated Encodable, Sendable {
    var name: String
    var volumePath: String
    var description: String = ""
    var recycleBinEnabled = true
    var recycleBinAdminOnly = true
    var hidden = false
    var hidesUnreadableItems = false
    /// Data checksum. Offered at creation only, exactly as in DSM: the choice cannot be
    /// revisited afterwards.
    var checksumEnabled = false
    var compressionEnabled = false
    /// Quota in megabytes; `nil` and `0` both mean no quota.
    var quotaMegabytes: Int?
    /// `nil` creates a plain folder; a non-empty key creates an encrypted one.
    var encryptionKey: String?
}

extension SharedFolderCreation {
    enum CodingKeys: String, CodingKey {
        case name, desc, encryption, hidden
        case volPath = "vol_path"
        case enableRecycleBin = "enable_recycle_bin"
        case recycleBinAdminOnly = "recycle_bin_admin_only"
        case hideUnreadable = "hide_unreadable"
        case checksum = "enable_share_cow"
        case compression = "enable_share_compress"
        case quota = "share_quota"
        case encryptionPassword = "enc_passwd"
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(volumePath, forKey: .volPath)
        try container.encode(description, forKey: .desc)
        try container.encode(recycleBinEnabled, forKey: .enableRecycleBin)
        try container.encode(recycleBinAdminOnly, forKey: .recycleBinAdminOnly)
        try container.encode(hidden, forKey: .hidden)
        try container.encode(hidesUnreadableItems, forKey: .hideUnreadable)
        try container.encode(checksumEnabled, forKey: .checksum)
        try container.encode(compressionEnabled, forKey: .compression)
        try container.encode(quotaMegabytes ?? 0, forKey: .quota)
        if let encryptionKey, !encryptionKey.isEmpty {
            try container.encode(true, forKey: .encryption)
            try container.encode(encryptionKey, forKey: .encryptionPassword)
        }
    }
}

/// Rules the encryption key has to satisfy, because DSM enforces none of its own: the API
/// accepts a three-letter key, and even an absent one, then encrypts the folder with it and
/// never lets it be unlocked again. Measured on DSM 7.4.
enum ShareEncryptionKey {
    /// Long enough to be worth having, short enough not to fight the user.
    static let minimumLength = 8

    /// The message explaining why this key cannot be used, or `nil` when it can.
    static func problem(key: String, confirmation: String) -> String? {
        if key.count < minimumLength {
            return String(localized: "shares.encryption.key.too_short")
        }
        if key != confirmation {
            return String(localized: "shares.encryption.key.mismatch")
        }
        return nil
    }
}

// MARK: - Editing

/// Encryption change requested on an existing folder. Both directions rewrite the folder's
/// contents through a DSM background task, so neither is instant.
enum ShareEncryptionChange: Sendable, Equatable {
    case encrypt(key: String)
    case decrypt(key: String)
}

/// `shareinfo` object sent to `SYNO.Core.Share` `set`.
///
/// DSM answers **403** unless both `name` and `vol_path` are present; every other field is
/// optional and only the ones supplied are applied.
struct SharedFolderChanges: nonisolated Encodable, Sendable {
    /// The three restrictions DSM groups under "Advanced permissions". They are written inside
    /// an `advanceperm` object but read back as three plain fields.
    struct AdvancedPermissions: nonisolated Encodable, Sendable, Equatable {
        var disablesListing: Bool
        var disablesModification: Bool
        var disablesDownload: Bool

        enum CodingKeys: String, CodingKey {
            case disablesListing = "disable_list"
            case disablesModification = "disable_modify"
            case disablesDownload = "disable_download"
        }
    }

    let name: String
    let volumePath: String
    var description: String?
    var recycleBinEnabled: Bool?
    var recycleBinAdminOnly: Bool?
    var hidden: Bool?
    var hidesUnreadableItems: Bool?
    var compressionEnabled: Bool?
    /// Quota in megabytes; `0` removes it.
    var quotaMegabytes: Int?
    var advancedPermissions: AdvancedPermissions?
    var encryption: ShareEncryptionChange?

    /// True when nothing would be written, so the view model can skip the call entirely.
    var isEmpty: Bool {
        description == nil
            && recycleBinEnabled == nil
            && recycleBinAdminOnly == nil
            && hidden == nil
            && hidesUnreadableItems == nil
            && compressionEnabled == nil
            && quotaMegabytes == nil
            && advancedPermissions == nil
            && encryption == nil
    }
}

extension SharedFolderChanges {
    enum CodingKeys: String, CodingKey {
        case name, desc, encryption, hidden, advanceperm
        case volPath = "vol_path"
        case enableRecycleBin = "enable_recycle_bin"
        case recycleBinAdminOnly = "recycle_bin_admin_only"
        case hideUnreadable = "hide_unreadable"
        case compression = "enable_share_compress"
        case quota = "share_quota"
        case encryptionPassword = "enc_passwd"
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(volumePath, forKey: .volPath)
        try container.encodeIfPresent(description, forKey: .desc)
        try container.encodeIfPresent(recycleBinEnabled, forKey: .enableRecycleBin)
        try container.encodeIfPresent(recycleBinAdminOnly, forKey: .recycleBinAdminOnly)
        try container.encodeIfPresent(hidden, forKey: .hidden)
        try container.encodeIfPresent(hidesUnreadableItems, forKey: .hideUnreadable)
        try container.encodeIfPresent(compressionEnabled, forKey: .compression)
        try container.encodeIfPresent(quotaMegabytes, forKey: .quota)
        try container.encodeIfPresent(advancedPermissions, forKey: .advanceperm)
        switch encryption {
        case .encrypt(let key):
            try container.encode(true, forKey: .encryption)
            try container.encode(key, forKey: .encryptionPassword)
        case .decrypt(let key):
            try container.encode(false, forKey: .encryption)
            try container.encode(key, forKey: .encryptionPassword)
        case nil:
            break
        }
    }
}

// MARK: - Background conversion

/// Answer of `SYNO.Core.Share` `set`. Turning encryption on or off hands back the identifier of
/// the background task that rewrites the folder; every other change answers without one.
struct ShareUpdateResult: nonisolated Decodable, Sendable {
    let taskID: String?

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
    }
}

/// Progress of that conversion, from `SYNO.Core.Share` `move_status`.
///
/// The full answer also repeats the original request, **encryption key included in clear**.
/// Only the two values below are decoded, and this type must never be logged as a whole.
struct ShareConversionStatus: nonisolated Decodable, Sendable {
    let finished: Bool
    let percent: Int

    enum CodingKeys: String, CodingKey {
        case finish, data
    }

    enum ProgressKeys: String, CodingKey {
        case percent
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        finished = values.flexBool(.finish) ?? false
        let progress = try? values.nestedContainer(keyedBy: ProgressKeys.self, forKey: .data)
        // DSM reports no percentage at all while it is still checking the folder.
        percent = progress?.flexInt(.percent) ?? 0
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

    /// An absent flag means the recycle bin was never enabled, which is what DSM's own edit
    /// screen shows, so it reads as "No" rather than as an unknown value.
    var recycleBinDescription: String {
        recycleBinEnabled == true
            ? String(localized: "common.answer.yes")
            : String(localized: "common.answer.no")
    }

    var encryptionDescription: String {
        switch encryptionState {
        case .none: String(localized: "common.answer.no")
        case .locked: String(localized: "shares.encryption.state.locked")
        case .mounted: String(localized: "shares.encryption.state.mounted")
        }
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableName: String { displayName }
    var sortableVolume: String { volumeText ?? "" }
    var sortableDescription: String { desc ?? "" }
    /// Sorted as text like `NASConnection.sortableTwoFactor`: `Bool` is not `Comparable`.
    var sortableRecycleBin: String { recycleBinEnabled == true ? "1" : "0" }
    var sortableEncryption: Int { encryptionState.rawValue }
}
