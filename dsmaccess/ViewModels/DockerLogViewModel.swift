//
//  DockerLogViewModel.swift
//  dsmaccess
//
//  Container Manager's event log: server-side filtering, export and clearing.
//

import Foundation
import Observation

@MainActor
@Observable
final class DockerLogViewModel {
    /// One request covers the whole log of a personal NAS (615 entries on the reference
    /// machine); the server-side filters narrow it further.
    static let pageSize = auditCappedPageLimit(1000)

    private(set) var entries: [DockerLogEntry] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var isExporting = false
    var level = DockerLogLevelFilter.all
    var searchText = ""
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = !silently
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let page = try await session.withClient {
                try await $0.dockerLog(
                    offset: 0,
                    limit: Self.pageSize,
                    level: level,
                    keyword: searchText
                )
            }
            guard generation == loadGeneration else { return }
            entries = page.entries
            total = page.total
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clear() async -> DSMOperationOutcome {
        do {
            try await session.withClient { try await $0.clearDockerLog() }
            await load(silently: true)
            return .success(String(localized: "containers.log.clear.success"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.operation_failed", defaultValue: "The operation failed: \(reason)"))
        }
    }

    func export(format: DockerLogExportFormat, to destination: URL) async -> DSMOperationOutcome {
        isExporting = true
        defer { isExporting = false }
        do {
            try await session.withClient {
                try await $0.exportDockerLog(format: format, to: destination)
            }
            return .success(String(
                localized: "logs.export.success",
                defaultValue: "Log exported to \(destination.lastPathComponent)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "logs.export.error", defaultValue: "Could not export: \(reason)"))
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        if entries.count < total {
            return String(
                localized: "containers.log.summary.partial",
                defaultValue: "\(entries.count) events shown of \(total)"
            )
        }
        return String(
            localized: "containers.log.summary.count",
            defaultValue: "\(total) events"
        )
    }
}
