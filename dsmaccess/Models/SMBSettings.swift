//
//  SMBSettings.swift
//  dsmaccess
//
//  Settings of the SMB file service (SYNO.Core.FileServ.SMB v3), measured on DSM 7.4 on
//  2026/08/29 by carrying the operation out in DSM with the traffic intercepted.
//
//  Two properties of the API shape this file:
//  — `get` returns 38 fields, but there is no single `set`. Applying the main screen sends
//    five fields; saving the "Advanced settings" dialog sends twenty-nine others. Mixing the
//    two in one call was never measured, so the two groups stay apart here.
//  — `smb_transfer_log_enable` does not exist in `get`. Whether SMB transfers are logged is
//    READ from SYNO.Core.SyslogClient.FileTransfer (field `cifs`) and WRITTEN by this basic
//    `set`. It is therefore not a property of the settings but a separate argument, so that
//    no caller can send it without having read it first.
//
//  The enumerated fields are decoded strictly: an unknown value fails the whole read rather
//  than being silently coerced. On DSM 7 their ranges are fixed, and a value outside them
//  would mean the contract changed — something to see, not to absorb.
//

import Foundation

/// SMB dialect, as DSM numbers it. ⚠️ The number is not the version: 1 means SMB2, and the
/// minimum and the maximum do not accept the same values.
enum SMBProtocolVersion: Int, nonisolated Codable, Sendable, CaseIterable, Identifiable {
    case smb1 = 0
    case smb2 = 1
    case smb2LargeMTU = 2
    case smb3 = 3

    var id: Int { rawValue }

    /// Values DSM offers for the minimum protocol. SMB3 is absent: it is a ceiling, not a floor.
    static let minimumChoices: [SMBProtocolVersion] = [.smb1, .smb2, .smb2LargeMTU]
    /// Values DSM offers for the maximum protocol. SMB1 is absent for the symmetric reason.
    static let maximumChoices: [SMBProtocolVersion] = [.smb2, .smb2LargeMTU, .smb3]

    var displayName: String {
        switch self {
        case .smb1: return String(localized: "smb.protocol.smb1")
        case .smb2: return String(localized: "smb.protocol.smb2")
        case .smb2LargeMTU: return String(localized: "smb.protocol.smb2_large_mtu")
        case .smb3: return String(localized: "smb.protocol.smb3")
        }
    }
}

/// Whether SMB traffic is encrypted, and who decides.
enum SMBTransportEncryption: Int, nonisolated Codable, Sendable, CaseIterable, Identifiable {
    case disabled = 0
    case clientDefined = 1
    case forced = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return String(localized: "smb.encryption.disabled")
        case .clientDefined: return String(localized: "smb.encryption.client_defined")
        case .forced: return String(localized: "smb.encryption.forced")
        }
    }
}

/// Server signing. ⚠️ Despite its `enable_` name the field is not a boolean, and its zero
/// does not mean "off": it disables SMB1 signing only.
enum SMBServerSigning: Int, nonisolated Codable, Sendable, CaseIterable, Identifiable {
    case smb1Only = 0
    case clientDefined = 1
    case forced = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .smb1Only: return String(localized: "smb.signing.smb1_only")
        case .clientDefined: return String(localized: "smb.signing.client_defined")
        case .forced: return String(localized: "smb.signing.forced")
        }
    }
}

/// The five fields the main SMB screen applies.
struct SMBBasicSettings: nonisolated Decodable, Sendable, Equatable {
    var isEnabled: Bool
    var workgroup: String
    /// Windows "previous versions", served from the shared folder snapshots.
    var deniesPreviousVersions: Bool
    var hidesUnauthorizedShares: Bool

    enum CodingKeys: String, CodingKey {
        case isEnabled = "enable_samba"
        case workgroup
        case deniesPreviousVersions = "disable_shadow_copy"
        case hidesUnauthorizedShares = "enable_access_based_share_enum"
    }
}

/// The twenty-eight fields the "Advanced settings" dialog applies, beside `enable_samba`
/// which it repeats from the main screen.
///
/// `enable_vetofile` and `enable_delete_vetofiles` are carried without being editable: the
/// dialog sends them on every save, so dropping them would reset a configuration the app
/// cannot yet offer. Their companion `vetofile`, which holds the patterns, is absent from
/// the measured call and is therefore neither read back nor sent.
struct SMBAdvancedSettings: nonisolated Decodable, Sendable, Equatable {
    var winsServer: String
    var maximumProtocol: SMBProtocolVersion
    var minimumProtocol: SMBProtocolVersion
    var transportEncryption: SMBTransportEncryption
    var serverSigning: SMBServerSigning
    var opportunisticLocking: Bool
    var smb2FileLeases: Bool
    var smb3DirectoryLeasing: Bool
    var durableHandles: Bool
    var macCharacterConversion: Bool
    var crossProtocolLockingWithAFP: Bool
    var localMasterBrowser: Bool
    var directorySorting: Bool
    var vetoesFiles: Bool
    var deletesDirectoriesHoldingVetoedFiles: Bool
    var symbolicLinks: Bool
    var wideLinks: Bool
    var resetsOnZeroVirtualCircuit: Bool
    var debugLogging: Bool
    var defaultUnixPermissions: Bool
    var skipsDiskAllocation: Bool
    var ntlmv1Authentication: Bool
    var asynchronousRead: Bool
    var subfolderChangeNotification: Bool
    var immediateSync: Bool
    var smb3Multichannel: Bool
    var wildcardSearchCache: Bool
    var performanceAnalysis: Bool

    enum CodingKeys: String, CodingKey {
        case winsServer = "wins"
        case maximumProtocol = "smb_max_protocol"
        case minimumProtocol = "smb_min_protocol"
        case transportEncryption = "smb_encrypt_transport"
        case serverSigning = "enable_server_signing"
        case opportunisticLocking = "enable_op_lock"
        case smb2FileLeases = "enable_smb2_leases"
        case smb3DirectoryLeasing = "enable_smb3_directory_leasing"
        case durableHandles = "enable_durable_handles"
        case macCharacterConversion = "enable_syno_catia"
        case crossProtocolLockingWithAFP = "enable_fruit_locking"
        case localMasterBrowser = "enable_local_master_browser"
        case directorySorting = "enable_dirsort"
        case vetoesFiles = "enable_vetofile"
        case deletesDirectoriesHoldingVetoedFiles = "enable_delete_vetofiles"
        case symbolicLinks = "enable_symlink"
        case wideLinks = "enable_widelink"
        case resetsOnZeroVirtualCircuit = "enable_reset_on_zero_vc"
        case debugLogging = "enable_enhance_log"
        case defaultUnixPermissions = "enable_mask"
        case skipsDiskAllocation = "disable_strict_allocate"
        case ntlmv1Authentication = "enable_ntlmv1_auth"
        case asynchronousRead = "enable_aio_read"
        case subfolderChangeNotification = "enable_synotify"
        case immediateSync = "enable_strict_sync"
        case smb3Multichannel = "enable_multichannel"
        case wildcardSearchCache = "syno_wildcard_search"
        case performanceAnalysis = "enable_perf_chart"
    }
}

/// One `get` fills both groups: DSM returns a single flat object, the split belongs to the
/// two `set` calls.
struct SMBSettings: nonisolated Decodable, Sendable, Equatable {
    var basic: SMBBasicSettings
    var advanced: SMBAdvancedSettings

    init(basic: SMBBasicSettings, advanced: SMBAdvancedSettings) {
        self.basic = basic
        self.advanced = advanced
    }

    init(from decoder: any Decoder) throws {
        basic = try SMBBasicSettings(from: decoder)
        advanced = try SMBAdvancedSettings(from: decoder)
    }
}
