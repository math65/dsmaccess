//
//  DSMLogSecurityService.swift
//  dsmaccess
//
//  Consultation des journaux DSM et des adresses bloquées.
//

import Foundation

@MainActor
final class DSMLogSecurityService {
    private static let logAPI = DSMAPI("SYNO.Core.SyslogClient.Log")
    private static let blockAPINames = [
        "SYNO.Core.Security.AutoBlock",
        "SYNO.Core.SmartBlock.Untrusted",
    ]

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func logs(limit: Int = 500) async throws -> [SystemLogEntry] {
        let result = try await transport.value(
            api: Self.logAPI,
            method: "list",
            parameters: [
                "offset": "0",
                "limit": String(limit),
                "sort_by": "time",
                "sort_direction": "DESC",
            ],
            as: SystemLogList.self
        )
        return result.logs
    }

    func blockedAddresses() async throws -> [BlockedAddress] {
        guard let api = blockAPI else { return [] }
        let result = try await transport.value(
            api: api,
            method: "list",
            parameters: ["offset": "0", "limit": "-1"],
            as: BlockedAddressList.self
        )
        return result.addresses.filter { !$0.address.isEmpty }
    }

    func unblock(_ address: String) async throws {
        guard let api = blockAPI else { throw DSMError.unsupportedAPI(Self.blockAPINames[0]) }
        try await transport.perform(
            api: api,
            method: "delete",
            parameters: ["ip": try DSMParameter.json([address])]
        )
    }

    private var blockAPI: DSMAPI? {
        Self.blockAPINames
            .first { transport.capabilities.supports($0) }
            .map { DSMAPI($0) }
    }
}
