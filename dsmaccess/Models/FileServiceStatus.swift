//
//  FileServiceStatus.swift
//  dsmaccess
//
//  Services de partage de fichiers du Panneau de configuration (SMB, NFS, FTP, rsync).
//  Chaque service a sa propre API (non documentée) : on lit son drapeau d'activation via
//  `get` et on le bascule via `set`.
//
//  Noms confirmés sur DSM 7.4 :
//   - SMB   : SYNO.Core.FileServ.SMB  → champ « enable_samba » (et non « enable_smb »)
//   - NFS   : SYNO.Core.FileServ.NFS  → champ « enable_nfs »
//   - FTP   : SYNO.Core.FileServ.FTP  → champ « enable_ftp »
//   - rsync : SYNO.Backup.Service.NetworkBackup → champ « enable » (rsync ne vit PAS dans
//             la famille SYNO.Core.FileServ.*, d'où l'erreur 102 attendue sur ce nom).
//  AFP est absent : Synology l'a retiré depuis DSM 7.2.
//

import Foundation

/// Un service de partage de fichiers réseau exposé par DSM.
enum FileService: String, CaseIterable, Identifiable, Sendable {
    case smb
    case nfs
    case ftp
    case rsync

    var id: String { rawValue }

    /// API correspondante (résolue via SYNO.API.Info, comme les autres modules).
    var api: String {
        switch self {
        case .smb: return "SYNO.Core.FileServ.SMB"
        case .nfs: return "SYNO.Core.FileServ.NFS"
        case .ftp: return "SYNO.Core.FileServ.FTP"
        case .rsync: return "SYNO.Backup.Service.NetworkBackup"
        }
    }

    /// Clé du drapeau d'activation dans la réponse `get` (et paramètre du `set`).
    var enableKey: String {
        switch self {
        case .smb: return "enable_samba"
        case .nfs: return "enable_nfs"
        case .ftp: return "enable_ftp"
        case .rsync: return "enable"
        }
    }

    /// Nom affiché (protocole + contexte d'usage).
    var displayName: String {
        switch self {
        case .smb: return String(localized: "files.service.smb")
        case .nfs: return String(localized: "files.service.nfs")
        case .ftp: return String(localized: "files.service.ftp")
        case .rsync: return String(localized: "files.service.rsync")
        }
    }
}

/// Réponse `get` d'un service de fichiers. On ne déclare que les drapeaux d'activation
/// connus, tous optionnels : DSM renvoie beaucoup d'autres champs qu'on ignore, et un
/// service donné ne renseigne que le sien.
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

    /// Drapeau d'activation pour le service demandé (nil s'il est absent de la réponse).
    func enabled(for service: FileService) -> Bool? {
        switch service {
        case .smb: return enableSMB
        case .nfs: return enableNFS
        case .ftp: return enableFTP
        case .rsync: return enableRsync
        }
    }
}
