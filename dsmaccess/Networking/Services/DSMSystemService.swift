//
//  DSMSystemService.swift
//  dsmaccess
//
//  General information and instantaneous utilization of the NAS.
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

    /// Processes grouped by service, like the DSM task manager.
    func processGroups() async throws -> [ProcessGroup] {
        try await transport.read(
            api: Self.processGroupAPI,
            method: "list",
            as: ProcessGroupPage.self
        ).slices
    }

    /// Sessions open on the NAS. `get` is the method the web client uses; `list` also
    /// exists and returns the same shape.
    func connections() async throws -> [NASConnection] {
        try await transport.read(
            api: Self.connectionAPI,
            method: "get",
            as: NASConnectionPage.self
        ).items
    }

    /// Files currently open on the NAS. `limit` is sent the way the web client does: without
    /// it the NAS returns everything, but a busy NAS can hold hundreds of them. The returned
    /// total stays that of the whole set, which lets us state what is not shown rather than
    /// truncating silently.
    func openedFiles(limit: Int) async throws -> OpenedFilePage {
        try await transport.read(
            api: Self.fileHandleAPI,
            method: "get",
            parameters: ["limit": .integer(limit), "offset": .integer(0)],
            as: OpenedFilePage.self
        )
    }

    /// Alerts the NAS recorded when a resource crossed a threshold. The log goes back as far
    /// as recording stayed enabled: the page is bounded and the returned total stays that of
    /// the whole set.
    func resourceMonitorLogs(limit: Int) async throws -> ResourceMonitorLogPage {
        try await transport.read(
            api: Self.resourceLogAPI,
            method: "list",
            parameters: ["limit": .integer(limit), "offset": .integer(0)],
            as: ResourceMonitorLogPage.self
        )
    }

    /// The monitor only records its history if the setting is enabled; without it the log
    /// stays empty indefinitely. The screen needs that distinction so it does not present a
    /// disabled setting as a NAS with no incident.
    func resourceMonitorHistoryEnabled() async throws -> Bool {
        try await transport.read(
            api: Self.resourceSettingAPI,
            method: "get",
            as: ResourceMonitorSetting.self
        ).historyEnabled
    }

    /// Performance alarm rules. The log only records an alert when a rule is crossed:
    /// without a rule, there is nothing to detect.
    func performanceAlarmRules() async throws -> PerformanceAlarmRulePage {
        try await transport.read(
            api: Self.resourceAlarmAPI,
            method: "list",
            as: PerformanceAlarmRulePage.self
        )
    }

    /// Creates or edits a rule: DSM uses the same method for both and tells them apart by
    /// the presence of `id`. The target always goes in `service`, whatever the type, and
    /// `enable` is required in both cases — verified on the NAS, omitting it means refusal.
    ///
    /// Mutation: single-attempt path.
    func savePerformanceAlarmRule(_ draft: PerformanceAlarmRuleDraft) async throws {
        var parameters: [String: DSMParameter] = [
            "type": .integer(draft.kind.rawValue),
            "service": .string(draft.resolvedTarget),
            "resource": .integer(draft.resource.rawValue),
            "threshold": .integer(draft.threshold),
            "severity": .integer(draft.severity.rawValue),
            "enable": .boolean(draft.isEnabled),
        ]
        if let ruleID = draft.ruleID {
            parameters["id"] = .string(ruleID)
        }

        try await transport.perform(
            api: Self.resourceAlarmAPI,
            method: "set",
            parameters: parameters
        )
    }

    /// Turns rules on or off. DSM applies in batch: it expects the list of affected rules
    /// with their new state, not one toggle at a time.
    ///
    /// Mutation: single-attempt path.
    func setPerformanceAlarmRules(_ states: [(id: String, enabled: Bool)]) async throws {
        let payload = states.map { RuleState(id: $0.id, enable: $0.enabled) }
        try await transport.perform(
            api: Self.resourceAlarmAPI,
            method: "onoff",
            parameters: ["id_list": try .json(payload)]
        )
    }

    /// Deletes rules. Mutation: single-attempt path.
    func deletePerformanceAlarmRules(ids: [String]) async throws {
        try await transport.perform(
            api: Self.resourceAlarmAPI,
            method: "delete",
            parameters: ["id_list": try .json(ids)]
        )
    }

    private struct RuleState: Encodable {
        let id: String
        let enable: Bool
    }

    /// Mutation: single-attempt path.
    func setResourceMonitorHistory(enabled: Bool) async throws {
        try await transport.perform(
            api: Self.resourceSettingAPI,
            method: "set",
            parameters: ["enable_history": .boolean(enabled)]
        )
    }

    /// Drops the given sessions. DSM expects two separate lists depending on the protocol and
    /// accepts no session identifier: each entry is re-identified by the values `get`
    /// returned. Both parameters are always sent, even empty, as the web client does.
    ///
    /// Mutation: single-attempt path. The NAS is given a longer timeout than the default,
    /// since it closes network sessions before answering.
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
