//
//  HyperBackupViewModel.swift
//  dsmaccess
//
//  State and orchestration of Hyper Backup monitoring.
//

import Foundation
import Observation

@MainActor
@Observable
final class HyperBackupViewModel {
    private(set) var tasks: [HyperBackupTask] = []
    private(set) var isLoading = false
    private(set) var busyTaskIDs: Set<Int> = []
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if !silently { isLoading = true }
        errorMessage = nil
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            let loaded = try await session.withClient { client -> [HyperBackupTask] in
                var tasks = try await client.listHyperBackupTasks().sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                // Only a running task carries a progress block, so the extra call is made
                // solely for the tasks the list already reports as busy.
                for index in tasks.indices where tasks[index].status != "none" {
                    tasks[index].liveState = try? await client.hyperBackupTaskState(
                        id: tasks[index].taskID
                    )
                }
                return tasks
            }
            guard generation == loadGeneration else { return }
            tasks = loaded
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = reason(for: error)
        }
    }

    func details(taskID: Int) async throws -> HyperBackupTaskDetails {
        try await session.withClient { client in
            let target = try await client.hyperBackupTarget(taskID: taskID)
            let versions = try await client.hyperBackupVersions(taskID: taskID)
            // Statistics are only offered by destinations that advertise them.
            let statistics: HyperBackupStatistics? = target.capability?.supportsStatistics == true
                ? try? await client.hyperBackupStatistics(taskID: taskID)
                : nil
            return HyperBackupTaskDetails(
                target: target,
                versions: versions,
                statistics: statistics
            )
        }
    }

    func logs(taskID: Int, offset: Int = 0, limit: Int = 200) async throws -> HyperBackupLogPage {
        try await session.withClient {
            try await $0.hyperBackupLogs(taskID: taskID, offset: offset, limit: limit)
        }
    }

    func backUp(_ task: HyperBackupTask) async -> DSMOperationOutcome {
        await perform(taskID: task.taskID, action: String(localized: "hyper_backup.operation.start")) {
            try await $0.startHyperBackupTask(id: task.taskID)
            return String(localized: "hyper_backup.announcement.backup_started", defaultValue: "Backup started: \(task.name)")
        }
    }

    func cancel(_ task: HyperBackupTask) async -> DSMOperationOutcome {
        let state = task.effectiveState
        return await perform(taskID: task.taskID, action: String(localized: "hyper_backup.operation.cancel")) {
            try await $0.cancelHyperBackupTask(id: task.taskID, state: state)
            return String(localized: "hyper_backup.announcement.cancel_requested", defaultValue: "Cancellation requested: \(task.name)")
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let runningCount = tasks.count(where: \.isRunning)
        return String(localized: "hyper_backup.list.summary", defaultValue: "\(tasks.count) backup tasks, \(runningCount) running")
    }

    /// Spoken description of a running task, used by the status bar and by the announcement
    /// made when a backup finishes.
    func progressDescription(for task: HyperBackupTask) -> String {
        guard let progress = task.progress else { return task.statusDescription }
        guard progress.showsPercentage else {
            return String(localized: "hyper_backup.progress.stage_only", defaultValue: "\(task.name): \(progress.stepDescription)")
        }
        return String(localized: "hyper_backup.progress.stage_with_percentage", defaultValue: "\(task.name): \(progress.stepDescription), \(progress.percentage)%")
    }

    private func perform(
        taskID: Int,
        action: String,
        operation: (DSMClientProtocol) async throws -> String
    ) async -> DSMOperationOutcome {
        guard !busyTaskIDs.contains(taskID) else { return .cancelled }
        busyTaskIDs.insert(taskID)
        defer { busyTaskIDs.remove(taskID) }
        do {
            let message = try await session.withClient(operation)
            await load(silently: true)
            return .success(message)
        } catch {
            await load(silently: true)
            return failure(error, action: action)
        }
    }

    private func failure(_ error: Error, action: String) -> DSMOperationOutcome {
        guard !DSMError.isCancellation(error) else { return .cancelled }
        return .failure(String(localized: "hyper_backup.error.operation_failed", defaultValue: "Failed while \(action): \(reason(for: error))"))
    }

    private func reason(for error: Error) -> String {
        (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}

struct HyperBackupTaskDetails: Sendable {
    let target: HyperBackupTarget
    let versions: [HyperBackupVersion]
    /// Absent when the destination does not advertise statistics support.
    let statistics: HyperBackupStatistics?
}
