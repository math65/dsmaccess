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
    private static let transferLoggingAPI = DSMAPI("SYNO.Core.SyslogClient.FileTransfer")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    /// Page du journal système. `keyword` est filtré par le NAS lui-même ; le niveau, lui, ne
    /// l'est pas : vérifié sur DSM 7.4, le paramètre `level` est accepté puis ignoré, et le
    /// filtrage par gravité se fait donc côté app.
    ///
    /// ⚠️ `logtype` est indispensable : sans lui le NAS ne renvoie que le journal système, alors
    /// qu'il en tient un par protocole en plus de celui des connexions. Un type que le NAS ne
    /// connaît pas renvoie zéro entrée **sans erreur** — d'où l'intérêt de ne proposer que les
    /// journaux réellement actifs.
    func systemLogs(
        kind: SystemLogKind,
        limit: Int,
        offset: Int = 0,
        keyword: String? = nil
    ) async throws -> SystemLogPage {
        var parameters: [String: DSMParameter] = [
            "logtype": .string(kind.rawValue),
            "offset": .integer(offset),
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

    /// Protocoles dont les transferts sont journalisés. Détermine les journaux à proposer.
    func fileTransferLogging() async throws -> FileTransferLogging {
        try await transport.read(
            api: Self.transferLoggingAPI,
            method: "get",
            as: FileTransferLogging.self
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
