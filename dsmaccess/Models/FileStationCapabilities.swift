//
//  FileStationCapabilities.swift
//  dsmaccess
//
//  Capacités File Station documentées et annoncées par le NAS connecté.
//

import Foundation

struct FileStationInfo: nonisolated Decodable, Equatable, Sendable {
    let isManager: Bool
    let supportedVirtualProtocols: Set<String>
    let supportsSharing: Bool
    let hostname: String

    private enum CodingKeys: String, CodingKey {
        case isManager = "is_manager"
        case supportedVirtualProtocols = "support_virtual_protocol"
        case legacySupportedVirtualProtocols = "support_virtual"
        case supportsSharing = "support_sharing"
        case hostname
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isManager = try container.requiredFlexBool(.isManager)
        supportsSharing = try container.requiredFlexBool(.supportsSharing)
        hostname = try container.requiredFlexString(.hostname)
        let protocols = container.flexString(.supportedVirtualProtocols)
            ?? container.flexString(.legacySupportedVirtualProtocols)
            ?? ""
        supportedVirtualProtocols = Set(
            protocols.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty }
        )
    }
}

enum FileStationFeature: String, CaseIterable, Sendable {
    case information
    case browsing
    case metadata
    case search
    case virtualFolders
    case favorites
    case thumbnails
    case directorySize
    case checksum
    case writePermission
    case upload
    case download
    case sharing
    case createFolder
    case rename
    case copyMove
    case delete
    case extract
    case compress
    case backgroundTasks

    nonisolated var requiredAPI: DSMAPI {
        switch self {
        case .information:
            DSMAPI("SYNO.FileStation.Info", preferredVersion: 2, minimumVersion: 2)
        case .browsing, .metadata:
            DSMAPI("SYNO.FileStation.List", preferredVersion: 2)
        case .search:
            DSMAPI("SYNO.FileStation.Search", preferredVersion: 2, minimumVersion: 2)
        case .virtualFolders:
            DSMAPI("SYNO.FileStation.VirtualFolder", preferredVersion: 2, minimumVersion: 2)
        case .favorites:
            DSMAPI("SYNO.FileStation.Favorite", preferredVersion: 2)
        case .thumbnails:
            DSMAPI("SYNO.FileStation.Thumb", preferredVersion: 2)
        case .directorySize:
            DSMAPI("SYNO.FileStation.DirSize", preferredVersion: 2, minimumVersion: 2)
        case .checksum:
            DSMAPI("SYNO.FileStation.MD5", preferredVersion: 2, minimumVersion: 2)
        case .writePermission:
            DSMAPI("SYNO.FileStation.CheckPermission", preferredVersion: 3, minimumVersion: 3)
        case .upload:
            DSMAPI("SYNO.FileStation.Upload", preferredVersion: 3)
        case .download:
            DSMAPI("SYNO.FileStation.Download", preferredVersion: 2)
        case .sharing:
            DSMAPI("SYNO.FileStation.Sharing", preferredVersion: 3, minimumVersion: 3)
        case .createFolder:
            DSMAPI("SYNO.FileStation.CreateFolder", preferredVersion: 2)
        case .rename:
            DSMAPI("SYNO.FileStation.Rename", preferredVersion: 2)
        case .copyMove:
            DSMAPI("SYNO.FileStation.CopyMove", preferredVersion: 3, minimumVersion: 3)
        case .delete:
            DSMAPI("SYNO.FileStation.Delete", preferredVersion: 2)
        case .extract:
            DSMAPI("SYNO.FileStation.Extract", preferredVersion: 2, minimumVersion: 2)
        case .compress:
            DSMAPI("SYNO.FileStation.Compress", preferredVersion: 3, minimumVersion: 3)
        case .backgroundTasks:
            DSMAPI("SYNO.FileStation.BackgroundTask", preferredVersion: 3, minimumVersion: 3)
        }
    }
}

struct FileStationCapabilities: Equatable, Sendable {
    let supportedFeatures: Set<FileStationFeature>
    let information: FileStationInfo?

    nonisolated func supports(_ feature: FileStationFeature) -> Bool {
        supportedFeatures.contains(feature)
    }
}

enum FileConflictPolicy: String, CaseIterable, Identifiable, Sendable {
    case ask
    case skip
    case overwrite

    var id: Self { self }
}
