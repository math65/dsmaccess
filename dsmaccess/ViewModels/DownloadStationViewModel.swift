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

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        guard let client = session.client, let sid = session.sid else {
            session.clear()
            return
        }
        if !silently { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }

        do {
            tasks = try await client.listDownloadTasks(sid: sid).sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            statistic = try? await client.downloadStatistic(sid: sid)
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func create(uri: String, destination: String?) async -> String {
        guard let client = session.client, let sid = session.sid else {
            return String(localized: "Session expirée.")
        }
        do {
            try await client.createDownload(uri: uri, destination: destination, sid: sid)
            await load()
            return String(localized: "Téléchargement ajouté")
        } catch {
            return failure(error)
        }
    }

    func pause(ids: Set<String>) async -> String {
        await perform(ids: ids) { client, sid in
            try await client.pauseDownloads(ids: ids, sid: sid)
            return String(localized: "\(ids.count) téléchargements mis en pause")
        }
    }

    func resume(ids: Set<String>) async -> String {
        await perform(ids: ids) { client, sid in
            try await client.resumeDownloads(ids: ids, sid: sid)
            return String(localized: "\(ids.count) téléchargements repris")
        }
    }

    func delete(ids: Set<String>, forceComplete: Bool) async -> String {
        await perform(ids: ids) { client, sid in
            try await client.deleteDownloads(ids: ids, forceComplete: forceComplete, sid: sid)
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
        operation: (DSMClientProtocol, String) async throws -> String
    ) async -> String {
        guard !ids.isEmpty else { return String(localized: "Aucun téléchargement sélectionné") }
        guard let client = session.client, let sid = session.sid else {
            return String(localized: "Session expirée.")
        }
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }

        do {
            let message = try await operation(client, sid)
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
