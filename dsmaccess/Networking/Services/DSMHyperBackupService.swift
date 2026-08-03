//
//  DSMHyperBackupService.swift
//  dsmaccess
//
//  Hyper Backup monitoring through the contracts observed on the NAS and in the official
//  DSM client.
//

import Foundation

@MainActor
final class DSMHyperBackupService {
    /// `SYNO.Backup.Task` advertises versions 1 and 2, but `list`, `get` and `status` only
    /// answer on version 1 — version 2 replies "no such method".
    private static let taskAPI = DSMAPI("SYNO.Backup.Task", preferredVersion: 1)
    private static let targetAPI = DSMAPI("SYNO.Backup.Target", preferredVersion: 1)
    /// The mirror image of the above: `SYNO.Backup.Version` only lists on version 2.
    private static let versionAPI = DSMAPI("SYNO.Backup.Version", preferredVersion: 2, minimumVersion: 2)
    private static let logAPI = DSMAPI("SYNO.SDS.Backup.Client.Common.Log", preferredVersion: 1)
    private static let statisticAPI = DSMAPI("SYNO.SDS.Backup.Client.Common.Statistic", preferredVersion: 1)

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func tasks() async throws -> [HyperBackupTask] {
        try await transport.read(
            api: Self.taskAPI,
            method: "list",
            as: HyperBackupTaskList.self
        ).tasks
    }

    func state(taskID: Int) async throws -> HyperBackupTaskState {
        try await transport.read(
            api: Self.taskAPI,
            method: "status",
            parameters: ["task_id": .integer(taskID)],
            as: HyperBackupTaskState.self
        )
    }

    func target(taskID: Int) async throws -> HyperBackupTarget {
        try await transport.read(
            api: Self.targetAPI,
            method: "get",
            parameters: ["task_id": .integer(taskID)],
            as: HyperBackupTarget.self
        )
    }

    func versions(taskID: Int) async throws -> [HyperBackupVersion] {
        try await transport.read(
            api: Self.versionAPI,
            method: "list",
            parameters: ["task_id": .integer(taskID)],
            as: HyperBackupVersionList.self
        ).versions
    }

    func logs(taskID: Int, offset: Int, limit: Int) async throws -> HyperBackupLogPage {
        try await transport.read(
            api: Self.logAPI,
            method: "list",
            parameters: [
                "task_id": .integer(taskID),
                "offset": .integer(offset),
                "limit": .integer(limit),
            ],
            as: HyperBackupLogPage.self
        )
    }

    func statistics(taskID: Int) async throws -> HyperBackupStatistics {
        try await transport.read(
            api: Self.statisticAPI,
            method: "get",
            parameters: ["task_id": .integer(taskID)],
            as: HyperBackupStatistics.self
        )
    }

    func backUp(taskID: Int) async throws {
        try await transport.perform(
            api: Self.taskAPI,
            method: "backup",
            parameters: ["task_id": .integer(taskID)]
        )
    }

    /// Cancelling needs the task state alongside its identifier. Sending only `task_id`
    /// fails with error 4400 even while DSM reports the run as cancellable.
    func cancel(taskID: Int, state: String) async throws {
        try await transport.perform(
            api: Self.taskAPI,
            method: "cancel",
            parameters: [
                "task_id": .integer(taskID),
                "task_state": .string(state),
            ]
        )
    }
}
