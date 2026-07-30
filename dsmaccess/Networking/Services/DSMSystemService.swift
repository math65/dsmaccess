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
    private static let fileHandleAPI = DSMAPI("SYNO.Core.FileHandle")
    private static let resourceLogAPI = DSMAPI("SYNO.ResourceMonitor.Log")
    private static let resourceSettingAPI = DSMAPI("SYNO.ResourceMonitor.Setting")
    private static let resourceAlarmAPI = DSMAPI("SYNO.ResourceMonitor.EventRule")

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

    /// Fichiers actuellement ouverts sur le NAS. `limit` est envoyé comme le fait le client
    /// web : sans lui le NAS répond tout, mais un NAS chargé peut en tenir des centaines.
    /// Le total renvoyé reste celui de l'ensemble, ce qui permet de dire ce qui n'est pas
    /// montré plutôt que de tronquer en silence.
    func openedFiles(limit: Int) async throws -> OpenedFilePage {
        try await transport.read(
            api: Self.fileHandleAPI,
            method: "get",
            parameters: ["limit": .integer(limit), "offset": .integer(0)],
            as: OpenedFilePage.self
        )
    }

    /// Alertes que le NAS a enregistrées quand une ressource a franchi un seuil. Le journal
    /// remonte aussi loin que l'enregistrement est resté actif : la page est bornée et le
    /// total renvoyé reste celui de l'ensemble.
    func resourceMonitorLogs(limit: Int) async throws -> ResourceMonitorLogPage {
        try await transport.read(
            api: Self.resourceLogAPI,
            method: "list",
            parameters: ["limit": .integer(limit), "offset": .integer(0)],
            as: ResourceMonitorLogPage.self
        )
    }

    /// Le moniteur n'enregistre son historique que si le réglage est actif ; sans lui le
    /// journal reste vide indéfiniment. L'écran a besoin de la distinction pour ne pas
    /// présenter un réglage désactivé comme un NAS sans incident.
    func resourceMonitorHistoryEnabled() async throws -> Bool {
        try await transport.read(
            api: Self.resourceSettingAPI,
            method: "get",
            as: ResourceMonitorSetting.self
        ).historyEnabled
    }

    /// Nombre de règles d'alarme définies. Le journal ne consigne une alerte que lorsqu'une
    /// règle est franchie : ce compte distingue un NAS sans incident d'un NAS où rien ne peut
    /// être détecté.
    func resourceMonitorAlarmRuleCount() async throws -> Int {
        try await transport.read(
            api: Self.resourceAlarmAPI,
            method: "list",
            as: ResourceMonitorAlarmRuleCount.self
        ).total
    }

    /// Mutation : chemin sans nouvelle tentative.
    func setResourceMonitorHistory(enabled: Bool) async throws {
        try await transport.perform(
            api: Self.resourceSettingAPI,
            method: "set",
            parameters: ["enable_history": .boolean(enabled)]
        )
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
