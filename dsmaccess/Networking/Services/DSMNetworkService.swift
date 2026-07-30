//
//  DSMNetworkService.swift
//  dsmaccess
//
//  NAS identity and network configuration.
//

import Foundation

@MainActor
final class DSMNetworkService {
    private static let networkAPI = DSMAPI("SYNO.Core.Network")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func information() async throws -> NetworkInfo {
        try await transport.read(
            api: Self.networkAPI,
            method: "get",
            as: NetworkInfo.self
        )
    }
}
