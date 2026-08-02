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

    /// The direction used to be carried by an icon alone, which said nothing to VoiceOver.
    var localizedName: String {
        switch self {
        case .upload: String(localized: "common.operation.upload")
        case .download: String(localized: "common.operation.download")
        }
    }
}

enum FileTransferState: Equatable, Sendable {
    case queued
    case running
    case completed
    case cancelled
    case failed(String)

    var isActive: Bool {
        self == .queued || self == .running
    }

    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }

    /// The readable state lives here rather than in the view because the table sorts on it:
    /// sorting the case itself would order the rows by their English identifier while the
    /// column shows the translation.
    var localizedName: String {
        switch self {
        case .queued: String(localized: "common.status.waiting")
        case .running: String(localized: "common.status.in_progress")
        case .completed: String(localized: "common.status.done")
        case .cancelled: String(localized: "transfers.status.cancelled")
        case .failed: String(localized: "common.status.failed")
        }
    }

    var failureMessage: String? {
        if case .failed(let message) = self { message } else { nil }
    }
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

    var statusDescription: String { state.localizedName }
    var directionDescription: String { direction.localizedName }

    /// How much of the transfer is done, as text. A transfer whose total size DSM never
    /// reported has no percentage to show.
    var progressDescription: String {
        guard let fraction = progress?.fractionCompleted else { return "—" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    var transferredDescription: String {
        guard let progress else { return "—" }
        let completed = progress.completedBytes.formatted(.byteCount(style: .file))
        guard let total = progress.totalBytes else { return completed }
        return String(
            localized: "common.format.value_of_total",
            defaultValue: "\(completed) of \(total.formatted(.byteCount(style: .file)))"
        )
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableDirection: String { directionDescription }
    var sortableStatus: String { statusDescription }
    var sortableProgress: Double { progress?.fractionCompleted ?? -1 }
    var sortableTransferred: Int64 { progress?.completedBytes ?? -1 }
    var sortableMessage: String { state.failureMessage ?? "" }
}
