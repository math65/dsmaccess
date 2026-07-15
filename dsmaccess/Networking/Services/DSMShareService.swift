//
//  DSMShareService.swift
//  dsmaccess
//
//  Gestion des dossiers partagés DSM.
//

import Foundation

@MainActor
final class DSMShareService {
    private static let shareAPI = DSMAPI("SYNO.Core.Share")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func folders() async throws -> [SharedFolder] {
        let list = try await transport.value(
            api: Self.shareAPI,
            method: "list",
            parameters: ["additional": try DSMParameter.json(["recyclebin", "share_quota"])],
            as: ShareList.self
        )
        return list.shares ?? []
    }

    func create(name: String, volumePath: String, description: String) async throws {
        let shareInfo = ShareCreateInfo(name: name, volPath: volumePath, desc: description)
        try await transport.perform(
            api: Self.shareAPI,
            method: "create",
            parameters: [
                "name": .string(name),
                "shareinfo": try DSMParameter.json(shareInfo),
            ]
        )
    }

    func delete(name: String) async throws {
        try await transport.perform(
            api: Self.shareAPI,
            method: "delete",
            parameters: ["name": try DSMParameter.json([name])]
        )
    }
}
