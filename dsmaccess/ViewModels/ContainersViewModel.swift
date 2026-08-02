//
//  ContainersViewModel.swift
//  dsmaccess
//
//  Container state, lifecycle and logs.
//

import Foundation
import Observation

@MainActor
@Observable
final class ContainersViewModel {
    private(set) var containers: [ContainerItem] = []
    private(set) var logs: [ContainerLogEntry] = []
    private(set) var logsContainerName: String?
    private(set) var processes: [ContainerProcess] = []
    private(set) var processesContainerName: String?
    private(set) var isLoading = false
    private(set) var isLoadingLogs = false
    private(set) var isLoadingProcesses = false
    private(set) var statistics: ContainerStatistics?
    private(set) var statisticsContainerName: String?
    private(set) var isLoadingStatistics = false
    var statisticsErrorMessage: String?
    private(set) var busyNames: Set<String> = []
    var errorMessage: String?
    var logErrorMessage: String?
    var processErrorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0
    private var logGeneration = 0
    private var processGeneration = 0
    private var statisticsGeneration = 0

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

    func perform(_ action: ContainerAction, on container: ContainerItem) async -> DSMOperationOutcome {
        busyNames.insert(container.name)
        defer { busyNames.remove(container.name) }

        do {
            try await session.withClient {
                try await $0.performContainerAction(action, name: container.name)
            }
            await load(silently: true)
            switch action {
            case .start: return .success(String(localized: "containers.action.start.success", defaultValue: "Container started: \(container.name)"))
            case .stop: return .success(String(localized: "containers.action.stop.success", defaultValue: "Container stopped: \(container.name)"))
            case .restart: return .success(String(localized: "containers.action.restart.success", defaultValue: "Container restarted: \(container.name)"))
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(container.name): \(reason)"))
        }
    }

    func delete(_ container: ContainerItem) async -> DSMOperationOutcome {
        busyNames.insert(container.name)
        defer { busyNames.remove(container.name) }

        do {
            try await session.withClient { try await $0.deleteContainer(name: container.name) }
            await load(silently: true)
            return .success(String(
                localized: "containers.action.delete.success",
                defaultValue: "Container deleted: \(container.name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(container.name): \(reason)"))
        }
    }

    func forceStop(_ container: ContainerItem) async -> DSMOperationOutcome {
        await mutate(container) {
            try await self.session.withClient { try await $0.killContainer(name: container.name) }
        } success: {
            String(
                localized: "containers.action.force_stop.success",
                defaultValue: "Container force stopped: \(container.name)"
            )
        }
    }

    func reset(_ container: ContainerItem) async -> DSMOperationOutcome {
        await mutate(container) {
            try await self.session.withClient { try await $0.resetContainer(name: container.name) }
        } success: {
            String(
                localized: "containers.action.reset.success",
                defaultValue: "Container reset: \(container.name)"
            )
        }
    }

    func profile(of container: ContainerItem) async throws -> ContainerProfile {
        try await session.withClient { try await $0.containerProfile(name: container.name) }
    }

    /// Saves the edited profile. `editName` is what renames the container, so the announced
    /// result names the container as it is now called, not as it was.
    func updateProfile(
        of container: ContainerItem,
        editName: String,
        profile: ContainerProfile
    ) async -> DSMOperationOutcome {
        await mutate(container) {
            try await self.session.withClient {
                try await $0.updateContainerProfile(
                    name: container.name,
                    editName: editName,
                    profile: profile
                )
            }
        } success: {
            String(
                localized: "containers.settings.saved",
                defaultValue: "Settings saved for \(editName)"
            )
        }
    }

    /// What the folder picker needs to offer a destination for the exported profile.
    func shareNames() async throws -> [String] {
        try await session.withClient { try await $0.listShares() }.map(\.name)
    }

    func folders(in path: String) async throws -> [FileStationItem] {
        try await session.withClient { client in
            try await client.list(folderPath: path)
                .filter(\.isdir)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Writes the container's creation profile to a folder of the NAS. DSM names the file
    /// itself, so the result says where it landed rather than pretending the name was a choice.
    func exportProfile(
        of container: ContainerItem,
        to folderPath: String
    ) async -> DSMOperationOutcome {
        await mutate(container) {
            try await self.session.withClient {
                try await $0.exportContainerProfile(
                    name: container.name,
                    folderPath: folderPath
                )
            }
        } success: {
            String(
                localized: "containers.action.export_profile.success",
                defaultValue: "Settings exported to \(folderPath)/\(container.name).syno.json"
            )
        }
    }

    private func mutate(
        _ container: ContainerItem,
        _ operation: () async throws -> Void,
        success: () -> String
    ) async -> DSMOperationOutcome {
        busyNames.insert(container.name)
        defer { busyNames.remove(container.name) }

        do {
            try await operation()
            await load(silently: true)
            return .success(success())
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(
                localized: "common.error.failed_for_item",
                defaultValue: "Failed for \(container.name): \(reason)"
            ))
        }
    }

    /// Docker's counters for the container being looked at. The call returns every container at
    /// once, so the one on screen is picked out by identifier.
    func loadStatistics(for container: ContainerItem) async {
        statisticsGeneration += 1
        let generation = statisticsGeneration
        isLoadingStatistics = true
        statisticsErrorMessage = nil
        statisticsContainerName = container.name
        defer { if generation == statisticsGeneration { isLoadingStatistics = false } }

        do {
            let all = try await session.withClient { try await $0.containerStatistics() }
            guard generation == statisticsGeneration,
                  statisticsContainerName == container.name else { return }
            statistics = all[container.id]
            if statistics == nil {
                statisticsErrorMessage = String(localized: "containers.statistics.unavailable")
            }
        } catch {
            guard generation == statisticsGeneration,
                  statisticsContainerName == container.name,
                  !DSMError.isCancellation(error) else { return }
            statistics = nil
            statisticsErrorMessage = (error as? DSMError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func loadProcesses(for container: ContainerItem) async {
        processGeneration += 1
        let generation = processGeneration
        isLoadingProcesses = true
        processErrorMessage = nil
        processesContainerName = container.name
        defer { if generation == processGeneration { isLoadingProcesses = false } }

        do {
            let result = try await session.withClient {
                try await $0.containerProcesses(name: container.name)
            }
            guard generation == processGeneration, processesContainerName == container.name else { return }
            processes = result
        } catch {
            guard generation == processGeneration,
                  processesContainerName == container.name,
                  !DSMError.isCancellation(error) else { return }
            processes = []
            processErrorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
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
        return String(localized: "containers.summary.count", defaultValue: "\(containers.count) containers, \(running) running")
    }
}
