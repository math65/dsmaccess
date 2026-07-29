//
//  DSMSystemService.swift
//  dsmaccess
//
//  Informations générales et utilisation instantanée du NAS.
//

import Foundation

@MainActor
final class DSMSystemService {
    private static let infoAPI = DSMAPI("SYNO.DSM.Info", preferredVersion: 2)
    private static let utilizationAPI = DSMAPI("SYNO.Core.System.Utilization")
    private static let processAPI = DSMAPI("SYNO.Core.System.Process")
    private static let processGroupAPI = DSMAPI("SYNO.Core.System.ProcessGroup")
    private static let connectionAPI = DSMAPI("SYNO.Core.CurrentConnection")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func information() async throws -> SystemInfo {
        try await transport.read(
            api: Self.infoAPI,
            method: "getinfo",
            as: SystemInfo.self
        )
    }

    func resourceUsage() async throws -> ResourceUsage {
        try await transport.read(
            api: Self.utilizationAPI,
            method: "get",
            as: ResourceUsage.self
        )
    }

    func processes() async throws -> [SystemProcess] {
        try await transport.read(
            api: Self.processAPI,
            method: "list",
            as: SystemProcessPage.self
        ).process
    }

    /// Processus regroupés par service, comme le gestionnaire des tâches de DSM.
    func processGroups() async throws -> [ProcessGroup] {
        try await transport.read(
            api: Self.processGroupAPI,
            method: "list",
            as: ProcessGroupPage.self
        ).slices
    }

    /// Sessions ouvertes sur le NAS. `get` est la méthode qu'emploie le client web ;
    /// `list` existe aussi et renvoie la même forme.
    func connections() async throws -> [NASConnection] {
        try await transport.read(
            api: Self.connectionAPI,
            method: "get",
            as: NASConnectionPage.self
        ).items
    }
}
