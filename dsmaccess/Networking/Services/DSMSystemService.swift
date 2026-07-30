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

    /// Coupe les sessions indiquées. DSM attend deux listes distinctes selon le protocole et
    /// n'accepte pas d'identifiant de session : chaque entrée est réidentifiée par les valeurs
    /// que `get` a renvoyées. Les deux paramètres sont toujours envoyés, fût-ce vides, comme
    /// le fait le client web.
    ///
    /// Mutation : chemin sans nouvelle tentative. Un délai plus large que la valeur par défaut
    /// est laissé au NAS, qui ferme des sessions réseau avant de répondre.
    func kickConnections(_ references: [NASConnection.KickReference]) async throws {
        var webReferences: [WebConnectionReference] = []
        var serviceReferences: [ServiceConnectionReference] = []
        for reference in references {
            switch reference {
            case let .web(deviceID, account, resource, address):
                webReferences.append(
                    WebConnectionReference(did: deviceID, who: account, descr: resource, from: address)
                )
            case let .service(processID, type, account, address):
                serviceReferences.append(
                    ServiceConnectionReference(pid: processID, type: type, who: account, from: address)
                )
            }
        }

        try await transport.perform(
            api: Self.connectionAPI,
            method: "kick_connection",
            parameters: [
                "http_conn": try .json(webReferences),
                "service_conn": try .json(serviceReferences),
            ],
            timeoutInterval: 100
        )
    }

    private struct WebConnectionReference: Encodable {
        let did: String
        let who: String
        let descr: String
        let from: String
    }

    private struct ServiceConnectionReference: Encodable {
        let pid: Int
        let type: String
        let who: String
        let from: String
    }
}
