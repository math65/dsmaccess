//
//  DSMDownloadStationService.swift
//  dsmaccess
//
//  Gestion des tâches Download Station via les API publiées par Synology.
//

import Foundation

@MainActor
final class DSMDownloadStationService {
    private static let taskAPI = DSMAPI("SYNO.DownloadStation.Task")
    private static let statisticAPI = DSMAPI("SYNO.DownloadStation.Statistic")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func tasks() async throws -> [DownloadTask] {
        let result = try await transport.value(
            api: Self.taskAPI,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(-1),
                "additional": "detail,transfer,file",
            ],
            as: DownloadTaskList.self
        )
        return result.tasks
    }

    func statistic() async throws -> DownloadStatistic {
        try await transport.value(
            api: Self.statisticAPI,
            method: "getinfo",
            as: DownloadStatistic.self
        )
    }

    func create(uri: String, destination: String?) async throws {
        var parameters: [String: DSMParameter] = ["uri": .string(uri)]
        if let destination, !destination.isEmpty {
            parameters["destination"] = .string(destination)
        }
        try await transport.perform(api: Self.taskAPI, method: "create", parameters: parameters)
    }

    func pause(ids: Set<String>) async throws {
        try await action("pause", ids: ids)
    }

    func resume(ids: Set<String>) async throws {
        try await action("resume", ids: ids)
    }

    func delete(ids: Set<String>, forceComplete: Bool) async throws {
        try await transport.perform(
            api: Self.taskAPI,
            method: "delete",
            parameters: [
                "id": .string(ids.sorted().joined(separator: ",")),
                "force_complete": .boolean(forceComplete),
            ]
        )
    }

    private func action(_ method: String, ids: Set<String>) async throws {
        guard !ids.isEmpty else { return }
        try await transport.perform(
            api: Self.taskAPI,
            method: method,
            parameters: ["id": .string(ids.sorted().joined(separator: ","))]
        )
    }
}
