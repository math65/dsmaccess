//
//  DownloadStationViewModel.swift
//  dsmaccess
//
//  State and actions of Download Station.
//

import Foundation
import Observation

@MainActor
@Observable
final class DownloadStationViewModel {
    private(set) var tasks: [DownloadTask] = []
    private(set) var statistic: DownloadStatistic?
    private(set) var isLoading = false
    private(set) var busyIDs: Set<String> = []
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
            let result = try await session.withClient { client in
                let tasks = try await client.listDownloadTasks().sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                let statistic: DownloadStatistic?
                do {
                    statistic = try await client.downloadStatistic()
                } catch DSMError.sessionExpired {
                    throw DSMError.sessionExpired
                } catch {
                    statistic = nil
                }
                return (tasks, statistic)
            }
            guard generation == loadGeneration else { return }
            tasks = result.0
            statistic = result.1
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func create(uri: String, destination: String?) async -> DSMOperationOutcome {
        do {
            try await session.withClient { try await $0.createDownload(uri: uri, destination: destination) }
            await load()
            return .success(String(localized: "download.add.done.announcement"))
        } catch {
            return failure(error)
        }
    }

    func pause(ids: Set<String>) async -> DSMOperationOutcome {
        await perform(ids: ids) { client in
            try await client.pauseDownloads(ids: ids)
            return String(localized: "download.pause.done.announcement", defaultValue: "\(ids.count) downloads paused")
        }
    }

    func resume(ids: Set<String>) async -> DSMOperationOutcome {
        await perform(ids: ids) { client in
            try await client.resumeDownloads(ids: ids)
            return String(localized: "download.resume.done.announcement", defaultValue: "\(ids.count) downloads resumed")
        }
    }

    func delete(ids: Set<String>, forceComplete: Bool) async -> DSMOperationOutcome {
        await perform(ids: ids) { client in
            try await client.deleteDownloads(ids: ids, forceComplete: forceComplete)
            return String(localized: "download.delete.done.announcement", defaultValue: "\(ids.count) downloads removed")
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let active = tasks.filter { $0.canPause }.count
        return String(localized: "download.summary.count", defaultValue: "\(tasks.count) downloads, \(active) active")
    }

    private func perform(
        ids: Set<String>,
        operation: (DSMClientProtocol) async throws -> String
    ) async -> DSMOperationOutcome {
        guard !ids.isEmpty else {
            return .failure(String(localized: "download.selection.empty"))
        }
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }

        do {
            let message = try await session.withClient(operation)
            await load()
            return .success(message)
        } catch {
            await load(silently: true)
            return failure(error)
        }
    }

    private func failure(_ error: Error) -> DSMOperationOutcome {
        guard !DSMError.isCancellation(error) else { return .cancelled }
        let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        return .failure(String(localized: "common.error.operation_failed", defaultValue: "The operation failed: \(reason)"))
    }
}
