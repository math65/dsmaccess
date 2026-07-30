//
//  FileServiceStatus.swift
//  dsmaccess
//
//  File-sharing services of the Control Panel (SMB, NFS, FTP, rsync). Each service has its
//  own (undocumented) API: its enable flag is read through `get` and toggled through `set`.
//
//  Names confirmed on DSM 7.4:
//   - SMB   : SYNO.Core.FileServ.SMB  → field "enable_samba" (and not "enable_smb")
//   - NFS   : SYNO.Core.FileServ.NFS  → field "enable_nfs"
//   - FTP   : SYNO.Core.FileServ.FTP  → field "enable_ftp"
//   - rsync : SYNO.Backup.Service.NetworkBackup → field "enable" (rsync does NOT live in
//             the SYNO.Core.FileServ.* family, hence the expected error 102 on that name).
//  AFP is absent: Synology removed it as of DSM 7.2.
//

import Foundation

/// A network file-sharing service exposed by DSM.
enum FileService: String, CaseIterable, Identifiable, Sendable {
    case smb
    case nfs
    case ftp
    case rsync

    var id: String { rawValue }

    /// Matching API (resolved through SYNO.API.Info, like the other modules).
    var api: String {
        switch self {
        case .smb: return "SYNO.Core.FileServ.SMB"
        case .nfs: return "SYNO.Core.FileServ.NFS"
        case .ftp: return "SYNO.Core.FileServ.FTP"
        case .rsync: return "SYNO.Backup.Service.NetworkBackup"
        }
    }

    /// Key of the enable flag in the `get` response (and parameter of the `set`).
    var enableKey: String {
        switch self {
        case .smb: return "enable_samba"
        case .nfs: return "enable_nfs"
        case .ftp: return "enable_ftp"
        case .rsync: return "enable"
        }
    }

    /// Displayed name (protocol + usage context).
    var displayName: String {
        switch self {
        case .smb: return String(localized: "files.service.smb")
        case .nfs: return String(localized: "files.service.nfs")
        case .ftp: return String(localized: "files.service.ftp")
        case .rsync: return String(localized: "files.service.rsync")
        }
    }
}

/// `get` response of a file service. Only the known enable flags are declared, all
/// optional: DSM returns many other fields we ignore, and a given service fills in only
/// its own.
struct FileServiceStatus: nonisolated Decodable, Sendable {
    let enableSMB: Bool?
    let enableNFS: Bool?
    let enableFTP: Bool?
    let enableRsync: Bool?

    enum CodingKeys: String, CodingKey {
        case enableSMB = "enable_samba"
        case enableNFS = "enable_nfs"
        case enableFTP = "enable_ftp"
        case enableRsync = "enable"
    }

    /// Enable flag for the requested service (nil if absent from the response).
    func enabled(for service: FileService) -> Bool? {
        switch service {
        case .smb: return enableSMB
        case .nfs: return enableNFS
        case .ftp: return enableFTP
        case .rsync: return enableRsync
        }
    }
}
