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
    private var loadGeneration = 0
    private var logGeneration = 0

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
            let result = try await session.withClient { try await $0.listContainers() }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            guard generation == loadGeneration else { return }
            containers = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func perform(_ action: ContainerAction, on container: ContainerItem) async -> String {
        busyNames.insert(container.name)
        defer { busyNames.remove(container.name) }

        do {
            try await session.withClient {
                try await $0.performContainerAction(action, name: container.name)
            }
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
        logGeneration += 1
        let generation = logGeneration
        isLoadingLogs = true
        logErrorMessage = nil
        logsContainerName = container.name
        defer { if generation == logGeneration { isLoadingLogs = false } }

        do {
            let result = try await session.withClient { try await $0.containerLogs(name: container.name) }
            guard generation == logGeneration, logsContainerName == container.name else { return }
            logs = result
        } catch {
            guard generation == logGeneration,
                  logsContainerName == container.name,
                  !DSMError.isCancellation(error) else { return }
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
