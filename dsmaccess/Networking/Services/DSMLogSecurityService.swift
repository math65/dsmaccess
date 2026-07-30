//
//  DSMLogSecurityService.swift
//  dsmaccess
//
//  Journal système du NAS et liste de blocage du blocage automatique.
//

import Foundation

@MainActor
final class DSMLogSecurityService {
    private static let logAPI = DSMAPI("SYNO.Core.SyslogClient.Log")
    private static let blockListAPI = DSMAPI("SYNO.Core.Security.AutoBlock.Rules")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    /// Page du journal système. `keyword` est filtré par le NAS lui-même ; le niveau, lui, ne
    /// l'est pas : vérifié sur DSM 7.4, le paramètre `level` est accepté puis ignoré, et le
    /// filtrage par gravité se fait donc côté app.
    func systemLogs(limit: Int, keyword: String? = nil) async throws -> SystemLogPage {
        var parameters: [String: DSMParameter] = [
            "offset": .integer(0),
            "limit": .integer(limit),
            "sort_by": "time",
            "sort_direction": "DESC",
        ]
        if let keyword, !keyword.isEmpty {
            parameters["keyword"] = .string(keyword)
        }
        return try await transport.read(
            api: Self.logAPI,
            method: "list",
            parameters: parameters,
            as: SystemLogPage.self
        )
    }

    /// Adresses que le blocage automatique refuse.
    ///
    /// ⚠️ `SYNO.Core.Security.AutoBlock` n'a **pas** de méthode `list` : elle ne sert qu'aux
    /// réglages du blocage. L'appeler valait un code 103, signalé par un utilisateur avant
    /// d'être reproduit sur le NAS de développement. La liste vit dans `AutoBlock.Rules`, qui
    /// exige `action` et `type` — sans eux, le NAS répond 5100.
    func blockedAddresses(limit: Int) async throws -> BlockedAddressPage {
        try await transport.read(
            api: Self.blockListAPI,
            method: "list",
            parameters: [
                "action": .string("load"),
                "offset": .integer(0),
                "limit": .integer(limit),
                "type": .string(Self.denyList),
            ],
            as: BlockedAddressPage.self
        )
    }

    /// Retire des adresses de la liste de blocage. Mutation : chemin sans nouvelle tentative.
    func unblockAddresses(_ addresses: [String]) async throws {
        try await transport.perform(
            api: Self.blockListAPI,
            method: "delete",
            parameters: [
                "type": .string(Self.denyList),
                "ip": try .json(addresses),
            ]
        )
    }

    /// La même API sert la liste d'autorisation ; seule celle de blocage est exposée par l'app.
    private static let denyList = "deny"
}
