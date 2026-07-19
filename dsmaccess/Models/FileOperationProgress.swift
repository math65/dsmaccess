//
//  FileOperationProgress.swift
//  dsmaccess
//
//  État commun des tâches File Station non bloquantes.
//

import Foundation

enum FileOperationKind: String, Codable, Sendable {
    case copyMove = "SYNO.FileStation.CopyMove"
    case delete = "SYNO.FileStation.Delete"
    case extract = "SYNO.FileStation.Extract"
    case compress = "SYNO.FileStation.Compress"
    case directorySize = "SYNO.FileStation.DirSize"
    case checksum = "SYNO.FileStation.MD5"
}

struct FileOperationProgress: Equatable, Sendable {
    let kind: FileOperationKind
    let taskID: String
    let isFinished: Bool
    let fractionCompleted: Double?
    let processedSize: Int64?
    let totalSize: Int64?
    let processedItemCount: Int?
    let totalItemCount: Int?
    let currentPath: String?
    let destinationPath: String?

    var normalizedFraction: Double? {
        fractionCompleted.map { min(max($0, 0), 1) }
    }
}

struct FileOperationStatus: nonisolated Decodable, Sendable {
    let finished: Bool
    let progress: Double?
    let processedSize: Int64?
    let total: Int64?
    let processedCount: Int?
    let path: String?
    let processingPath: String?
    let destinationFolderPath: String?
    let destinationFilePath: String?

    private enum CodingKeys: String, CodingKey {
        case finished, progress, total, path
        case processedSize = "processed_size"
        case processedCount = "processed_num"
        case processingPath = "processing_path"
        case destinationFolderPath = "dest_folder_path"
        case destinationFilePath = "dest_file_path"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finished = try container.requiredFlexBool(.finished)
        progress = container.flexDouble(.progress)
        processedSize = container.flexInt64(.processedSize)
        total = container.flexInt64(.total)
        processedCount = container.flexInt(.processedCount)
        path = container.flexString(.path)
        processingPath = container.flexString(.processingPath)
        destinationFolderPath = container.flexString(.destinationFolderPath)
        destinationFilePath = container.flexString(.destinationFilePath)
    }
}

struct FileStationBackgroundTasks: nonisolated Decodable, Sendable {
    let total: Int
    let offset: Int
    let tasks: [FileStationBackgroundTask]

    private enum CodingKeys: String, CodingKey {
        case total, offset, tasks
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = try container.decode([FileStationBackgroundTask].self, forKey: .tasks)
        total = container.flexInt(.total) ?? tasks.count
        offset = container.flexInt(.offset) ?? 0
    }
}

struct FileStationBackgroundTask: nonisolated Decodable, Identifiable, Sendable {
    let api: String
    let version: String?
    let method: String?
    let taskID: String
    let finished: Bool
    let creationTime: Int?
    let path: String?
    let processedCount: Int?
    let processedSize: Int64?
    let processingPath: String?
    let total: Int64?
    let progress: Double?

    var id: String { taskID }

    private enum CodingKeys: String, CodingKey {
        case api, version, method, finished, path, total, progress
        case taskID = "taskid"
        case creationTime = "crtime"
        case processedCount = "processed_num"
        case processedSize = "processed_size"
        case processingPath = "processing_path"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        api = try container.requiredFlexString(.api)
        version = container.flexString(.version)
        method = container.flexString(.method)
        taskID = try container.requiredFlexString(.taskID)
        finished = try container.requiredFlexBool(.finished)
        creationTime = container.flexInt(.creationTime)
        path = container.flexString(.path)
        processedCount = container.flexInt(.processedCount)
        processedSize = container.flexInt64(.processedSize)
        processingPath = container.flexString(.processingPath)
        total = container.flexInt64(.total)
        progress = container.flexDouble(.progress)
    }
}

struct FileStationDirectorySize: Equatable, Sendable {
    let directoryCount: Int
    let fileCount: Int
    let totalSize: Int64
}

struct FileStationDirectorySizeStatus: nonisolated Decodable, Sendable {
    let finished: Bool
    let directoryCount: Int?
    let fileCount: Int?
    let totalSize: Int64?

    private enum CodingKeys: String, CodingKey {
        case finished
        case directoryCount = "num_dir"
        case fileCount = "num_file"
        case totalSize = "total_size"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finished = try container.requiredFlexBool(.finished)
        directoryCount = container.flexInt(.directoryCount)
        fileCount = container.flexInt(.fileCount)
        totalSize = container.flexInt64(.totalSize)
    }
}

struct FileStationChecksumStatus: nonisolated Decodable, Sendable {
    let finished: Bool
    let checksum: String?

    private enum CodingKeys: String, CodingKey {
        case finished
        case checksum = "md5"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        finished = try container.requiredFlexBool(.finished)
        checksum = container.flexString(.checksum)
    }
}
