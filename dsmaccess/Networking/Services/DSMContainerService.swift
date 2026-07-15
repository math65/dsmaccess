//
//  DSMContainerService.swift
//  dsmaccess
//
//  Inventaire, cycle de vie et journaux de Container Manager.
//

import Foundation

@MainActor
final class DSMContainerService {
    private static let containerAPI = DSMAPI("SYNO.Docker.Container", preferredVersion: 1)
    private static let logAPI = DSMAPI("SYNO.Docker.Container.Log", preferredVersion: 1)

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func containers() async throws -> [ContainerItem] {
        let result = try await transport.value(
            api: Self.containerAPI,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(-1),
                "additional": try DSMParameter.json(["resource"]),
            ],
            as: ContainerList.self
        )
        return result.containers
    }

    func perform(_ action: ContainerAction, name: String) async throws {
        try await transport.perform(
            api: Self.containerAPI,
            method: action.rawValue,
            parameters: ["name": .string(name)]
        )
    }

    func logs(name: String, limit: Int = 300) async throws -> [ContainerLogEntry] {
        guard transport.capabilities.supports(Self.logAPI.name) else { return [] }
        let result = try await transport.value(
            api: Self.logAPI,
            method: "get",
            parameters: [
                "name": .string(name),
                "offset": .integer(0),
                "limit": .integer(limit),
            ],
            as: ContainerLogList.self
        )
        return result.logs
    }
}
