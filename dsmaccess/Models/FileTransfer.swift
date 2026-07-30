//
//  FileTransfer.swift
//  dsmaccess
//
//  Local progress of File Station uploads and downloads.
//

import Foundation

struct DSMTransferProgress: Equatable, Sendable {
    let completedBytes: Int64
    let totalBytes: Int64?

    nonisolated init(completedBytes: Int64, totalBytes: Int64?) {
        self.completedBytes = max(0, completedBytes)
        self.totalBytes = totalBytes.flatMap { $0 > 0 ? $0 : nil }
    }

    var fractionCompleted: Double? {
        guard let totalBytes else { return nil }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }
}

typealias DSMTransferProgressHandler = @MainActor @Sendable (DSMTransferProgress) -> Void

enum FileTransferDirection: String, Sendable {
    case upload
    case download
}

enum FileTransferState: Equatable, Sendable {
    case queued
    case running
    case completed
    case cancelled
    case failed(String)
}

struct FileTransferRecord: Equatable, Identifiable, Sendable {
    let id: UUID
    let direction: FileTransferDirection
    let name: String
    let source: String
    let destination: String
    var progress: DSMTransferProgress?
    var state: FileTransferState

    nonisolated init(
        id: UUID = UUID(),
        direction: FileTransferDirection,
        name: String,
        source: String,
        destination: String,
        progress: DSMTransferProgress? = nil,
        state: FileTransferState = .queued
    ) {
        self.id = id
        self.direction = direction
        self.name = name
        self.source = source
        self.destination = destination
        self.progress = progress
        self.state = state
    }
}
