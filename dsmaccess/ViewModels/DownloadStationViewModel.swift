//
//  DownloadStationViewModel.swift
//  dsmaccess
//
//  État et actions de Download Station.
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

    func create(uri: String, destination: String?) async -> String {
        do {
            try await session.withClient { try await $0.createDownload(uri: uri, destination: destination) }
            await load()
            return String(localized: "Téléchargement ajouté")
        } catch {
            return failure(error)
        }
    }

    func pause(ids: Set<String>) async -> String {
        await perform(ids: ids) { client in
            try await client.pauseDownloads(ids: ids)
            return String(localized: "\(ids.count) téléchargements mis en pause")
        }
    }

    func resume(ids: Set<String>) async -> String {
        await perform(ids: ids) { client in
            try await client.resumeDownloads(ids: ids)
            return String(localized: "\(ids.count) téléchargements repris")
        }
    }

    func delete(ids: Set<String>, forceComplete: Bool) async -> String {
        await perform(ids: ids) { client in
            try await client.deleteDownloads(ids: ids, forceComplete: forceComplete)
            return String(localized: "\(ids.count) téléchargements supprimés")
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let active = tasks.filter { $0.canPause }.count
        return String(localized: "\(tasks.count) téléchargements, \(active) actifs")
    }

    private func perform(
        ids: Set<String>,
        operation: (DSMClientProtocol) async throws -> String
    ) async -> String {
        guard !ids.isEmpty else { return String(localized: "Aucun téléchargement sélectionné") }
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }

        do {
            let message = try await session.withClient(operation)
            await load()
            return message
        } catch {
            await load(silently: true)
            return failure(error)
        }
    }

    private func failure(_ error: Error) -> String {
        let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        return String(localized: "Échec de l’opération : \(reason)")
    }
}
