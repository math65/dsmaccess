//
//  ContainersViewModel.swift
//  dsmaccess
//
//  État, cycle de vie et journaux des conteneurs.
//

import Foundation
import Observation

@MainActor
@Observable
final class ContainersViewModel {
    private(set) var containers: [ContainerItem] = []
    private(set) var logs: [ContainerLogEntry] = []
    private(set) var logsContainerName: String?
    private(set) var isLoading = false
    private(set) var isLoadingLogs = false
    private(set) var busyNames: Set<String> = []
    var errorMessage: String?
    var logErrorMessage: String?

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
            containers = try await client.listContainers(sid: sid).sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func perform(_ action: ContainerAction, on container: ContainerItem) async -> String {
        guard let client = session.client, let sid = session.sid else {
            return String(localized: "Session expirée.")
        }
        busyNames.insert(container.name)
        defer { busyNames.remove(container.name) }

        do {
            try await client.performContainerAction(action, name: container.name, sid: sid)
            await load(silently: true)
            switch action {
            case .start: return String(localized: "Conteneur démarré : \(container.name)")
            case .stop: return String(localized: "Conteneur arrêté : \(container.name)")
            case .restart: return String(localized: "Conteneur redémarré : \(container.name)")
            }
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec pour \(container.name) : \(reason)")
        }
    }

    func loadLogs(for container: ContainerItem) async {
        guard let client = session.client, let sid = session.sid else { return }
        isLoadingLogs = true
        logErrorMessage = nil
        logsContainerName = container.name
        defer { isLoadingLogs = false }

        do {
            logs = try await client.containerLogs(name: container.name, sid: sid)
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            logs = []
            logErrorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let running = containers.filter(\.isRunning).count
        return String(localized: "\(containers.count) conteneurs, \(running) en fonctionnement")
    }
}
