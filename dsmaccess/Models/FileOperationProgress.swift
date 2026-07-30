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

    /// Nom de l'opération repris tel quel dans la liste des tâches et dans le bandeau de
    /// progression. DSM ne distingue pas la copie du déplacement une fois la tâche lancée.
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

    /// Résultat annoncé quand l'app reprend une tâche déjà lancée : le NAS ne dit pas
    /// combien d'éléments elle a traités, seulement qu'elle est terminée.
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
}

/// Vitesse et temps restant d'une opération, déduits de relevés successifs : DSM ne les
/// donne jamais, seul l'écart entre deux `processed_size` les révèle. Une copie les expose
/// donc, une compression non — elle ne rapporte aucun volume traité.
struct FileOperationRate: Equatable, Sendable {
    private struct Sample: Equatable, Sendable {
        let date: Date
        let bytes: Int64
    }

    /// Fenêtre glissante : la vitesse instantanée saute d'un relevé à l'autre, et une
    /// moyenne depuis le début cesse de suivre quand le débit change en cours de route.
    private static let windowLength = 8
    /// Rien n'est estimé avant d'avoir de quoi être stable : une estimation qui passe de
    /// deux à quarante minutes est plus nuisible qu'une absence d'estimation.
    private static let minimumSamples = 4

    private var samples: [Sample] = []
    private var taskID: String?

    mutating func record(_ progress: FileOperationProgress, at date: Date = .now) {
        guard let bytes = progress.processedSize else { return }
        // Une nouvelle tâche, ou un volume qui recule, invalide les relevés précédents.
        if taskID != progress.taskID || bytes < (samples.last?.bytes ?? 0) {
            samples.removeAll()
            taskID = progress.taskID
        }
        samples.append(Sample(date: date, bytes: bytes))
        if samples.count > Self.windowLength {
            samples.removeFirst(samples.count - Self.windowLength)
        }
    }

    /// Octets par seconde sur la fenêtre courante, ou `nil` tant qu'elle est trop courte.
    var bytesPerSecond: Double? {
        guard samples.count >= Self.minimumSamples,
              let first = samples.first, let last = samples.last else { return nil }
        let elapsed = last.date.timeIntervalSince(first.date)
        guard elapsed > 0 else { return nil }
        let rate = Double(last.bytes - first.bytes) / elapsed
        return rate > 0 ? rate : nil
    }

    /// Temps restant pour l'avancement donné, quand le NAS rapporte une taille totale.
    /// Une durée très courte est rendue telle quelle : c'est à l'affichage de dire
    /// « moins d'une minute » plutôt que d'égrener des secondes.
    func remaining(for progress: FileOperationProgress) -> Duration? {
        guard let rate = bytesPerSecond,
              let processed = progress.processedSize,
              let total = progress.totalSize, total > processed else { return nil }
        return .seconds(Double(total - processed) / rate)
    }
}

/// Le suivi d'une tâche s'est interrompu alors que le NAS la traite toujours : la demande
/// a été acceptée, seule la progression est perdue. À distinguer d'un échec, sinon
/// l'utilisateur relance une copie déjà en cours.
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
