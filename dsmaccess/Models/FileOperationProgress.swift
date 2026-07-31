//
//  FileOperationProgress.swift
//  dsmaccess
//
//  Shared state of non-blocking File Station tasks.
//

import Foundation

enum FileOperationKind: String, Codable, Sendable {
    case copyMove = "SYNO.FileStation.CopyMove"
    case delete = "SYNO.FileStation.Delete"
    case extract = "SYNO.FileStation.Extract"
    case compress = "SYNO.FileStation.Compress"
    case directorySize = "SYNO.FileStation.DirSize"
    case checksum = "SYNO.FileStation.MD5"

    /// Operation name used as is in the task list and in the progress banner. DSM does not
    /// distinguish a copy from a move once the task has started.
    var label: String {
        switch self {
        case .copyMove: String(localized: "files.progress.copy_move")
        case .delete: String(localized: "common.operation.deletion")
        case .extract: String(localized: "common.operation.extraction")
        case .compress: String(localized: "common.operation.compression")
        case .directorySize: String(localized: "files.progress.size")
        case .checksum: String(localized: "files.progress.md5")
        }
    }

    /// Result announced when the app picks up an already running task: the NAS does not say
    /// how many items it processed, only that it has finished.
    var completionMessage: String {
        switch self {
        case .copyMove: String(localized: "files.progress.copy_move.finished")
        case .delete: String(localized: "files.progress.deletion.finished")
        case .extract: String(localized: "files.progress.extraction.finished")
        case .compress: String(localized: "files.progress.compression.finished")
        case .directorySize: String(localized: "files.progress.size.finished")
        case .checksum: String(localized: "files.progress.md5.finished")
        }
    }
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

    var display: FileProgressDisplay {
        FileProgressDisplay(
            identity: taskID,
            fractionCompleted: fractionCompleted,
            processedSize: processedSize,
            totalSize: totalSize,
            processedItemCount: processedItemCount,
            totalItemCount: totalItemCount,
            currentPath: currentPath
        )
    }
}

/// What the progress banner actually reads. Kept apart from `FileOperationProgress`, whose
/// `kind` carries the name of a DSM API: uploads and downloads are HTTP transfers, not NAS
/// tasks, and giving them a fake API name to reach the banner would make the network model lie.
struct FileProgressDisplay: Equatable, Sendable {
    /// Distinguishes one run from the next. `FileOperationRate` drops its samples when this
    /// changes, so a second upload does not inherit the speed of the first.
    let identity: String
    let fractionCompleted: Double?
    let processedSize: Int64?
    let totalSize: Int64?
    let processedItemCount: Int?
    let totalItemCount: Int?
    let currentPath: String?

    var normalizedFraction: Double? {
        fractionCompleted.map { min(max($0, 0), 1) }
    }
}

/// Speed and remaining time of an operation, derived from successive samples: DSM never
/// provides them, only the gap between two `processed_size` values reveals them. A copy
/// therefore exposes them, a compression does not — it reports no processed volume.
struct FileOperationRate: Equatable, Sendable {
    private struct Sample: Equatable, Sendable {
        let date: Date
        let bytes: Int64
    }

    /// Sliding window: the instantaneous speed jumps from one sample to the next, and an
    /// average since the start stops keeping up when the throughput changes along the way.
    private static let windowLength = 8
    /// Nothing is estimated before there is enough to be stable: an estimate that goes from
    /// two to forty minutes is more harmful than no estimate at all.
    private static let minimumSamples = 4

    private var samples: [Sample] = []
    private var taskID: String?

    mutating func record(_ progress: FileProgressDisplay, at date: Date = .now) {
        guard let bytes = progress.processedSize else { return }
        // A new run, or a volume that goes backwards, invalidates the previous samples.
        if taskID != progress.identity || bytes < (samples.last?.bytes ?? 0) {
            samples.removeAll()
            taskID = progress.identity
        }
        samples.append(Sample(date: date, bytes: bytes))
        if samples.count > Self.windowLength {
            samples.removeFirst(samples.count - Self.windowLength)
        }
    }

    /// Bytes per second over the current window, or `nil` as long as it is too short.
    var bytesPerSecond: Double? {
        guard samples.count >= Self.minimumSamples,
              let first = samples.first, let last = samples.last else { return nil }
        let elapsed = last.date.timeIntervalSince(first.date)
        guard elapsed > 0 else { return nil }
        let rate = Double(last.bytes - first.bytes) / elapsed
        return rate > 0 ? rate : nil
    }

    /// Remaining time for the given progress, when the NAS reports a total size.
    /// A very short duration is returned as is: it is up to the display to say
    /// "less than a minute" rather than counting off seconds.
    func remaining(for progress: FileProgressDisplay) -> Duration? {
        guard let rate = bytesPerSecond,
              let processed = progress.processedSize,
              let total = progress.totalSize, total > processed else { return nil }
        return .seconds(Double(total - processed) / rate)
    }
}

/// Tracking of a task stopped while the NAS is still processing it: the request was
/// accepted, only the progress is lost. To be distinguished from a failure, otherwise the
/// user restarts a copy that is already running.
struct FileOperationTrackingInterrupted: Error {
    let kind: FileOperationKind
    let taskID: String
    let underlying: Error
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
