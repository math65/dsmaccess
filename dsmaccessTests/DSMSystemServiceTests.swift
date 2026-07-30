import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMSystemServiceTests {
    /// Contract captured on DSM 7.4: `kick_connection` takes no session identifier. It
    /// expects two lists, and sorting between the two depends on the protocol. A web session
    /// placed in `service_conn` — or the reverse — cuts nothing while still answering true.
    @Test func sendsTheTwoConnectionListsKickExpects() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.kickConnections([
            .web(deviceID: "jeton", account: "testeur", resource: "DiskStation Manager", address: "10.0.0.2"),
            .service(processID: 12908, type: "SMB3", account: "testeur", address: "10.0.0.3"),
        ])

        let requests = await stub.requests
        #expect(requests.count == 1)
        let parameters = try query(from: requests[0])
        #expect(parameters["api"] == "SYNO.Core.CurrentConnection")
        #expect(parameters["method"] == "kick_connection")

        let web = try decode([WebReference].self, from: parameters["http_conn"])
        #expect(web == [WebReference(did: "jeton", who: "testeur", descr: "DiskStation Manager", from: "10.0.0.2")])
        let service_ = try decode([ServiceReference].self, from: parameters["service_conn"])
        #expect(service_ == [ServiceReference(pid: 12908, type: "SMB3", who: "testeur", from: "10.0.0.3")])
    }

    /// The web client always sends both parameters. Omitting an empty one would risk DSM
    /// reading the remaining list as covering every protocol.
    @Test func sendsBothListsEvenWhenOneIsEmpty() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.kickConnections([
            .service(processID: 12908, type: "SMB3", account: "testeur", address: "10.0.0.3"),
        ])

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["http_conn"] == "[]")
        #expect(try decode([ServiceReference].self, from: parameters["service_conn"]).count == 1)
    }

    /// Cutting a session is a mutation: a timeout must not replay it. The NAS may have closed
    /// the sessions before answering, and a second attempt would then cut sessions reopened
    /// in the meantime.
    @Test func neverReplaysTheKickAfterATimeout() async throws {
        let stub = DSMRequestStub(results: [.timeout, .response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        do {
            try await service.kickConnections([
                .service(processID: 12908, type: "SMB3", account: "testeur", address: "10.0.0.3"),
            ])
            Issue.record("La coupure aurait dû échouer après le délai d’attente.")
        } catch {
            let dsmError = try #require(error as? DSMError)
            guard case .network = dsmError else {
                Issue.record("Erreur inattendue : \(dsmError)")
                return
            }
        }
        #expect(await stub.requestCount == 1)
    }

    /// A DSM error must surface as such: a failure presented as a success would suggest a
    /// session was closed while it stays open.
    @Test func reportsAKickRefusedByTheNAS() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":false,"error":{"code":105}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        await #expect(throws: DSMError.permissionDenied) {
            try await service.kickConnections([
                .web(deviceID: "jeton", account: "testeur", resource: "DiskStation Manager", address: "10.0.0.2"),
            ])
        }
    }

    /// The web client sends `limit` and `offset`; verified on the NAS, pagination is indeed
    /// honoured (2 out of 9 returned) and `total` stays that of the whole set. The screen
    /// relies on that gap to state what it is not showing.
    @Test func asksForABoundedPageOfOpenedFiles() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"""
            {"success":true,"data":{"OpenedFiles":[
              {"filename":"a.log","path":"App/a.log","pid":"1","service":"S","user":"-","host":"-"}],
              "total":9}}
            """#.utf8)),
        ])
        let service = makeService(stub: stub)

        let page = try await service.openedFiles(limit: 500)

        #expect(page.files.count == 1)
        #expect(page.total == 9)
        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Core.FileHandle")
        #expect(parameters["method"] == "get")
        #expect(parameters["limit"] == "500")
        #expect(parameters["offset"] == "0")
    }

    /// The web client paginates this log; the screen relies on the gap between the page and
    /// the total to state what it is not showing.
    @Test func asksForABoundedPageOfHistoryEntries() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"""
            {"success":true,"data":{"logs":[
              {"time":"2026/7/30 9:05:12","level":"Warning","event":"Charge du volume 1"}],
              "total":40}}
            """#.utf8)),
        ])
        let service = makeService(stub: stub)

        let page = try await service.resourceMonitorLogs(limit: 1000)

        #expect(page.entries.count == 1)
        #expect(page.total == 40)
        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.ResourceMonitor.Log")
        #expect(parameters["method"] == "list")
        #expect(parameters["limit"] == "1000")
        #expect(parameters["offset"] == "0")
    }

    /// The setting decides whether the log fills up. A misread answer would present a NAS
    /// that is recording as a silent one.
    @Test func readsWhetherTheNASRecordsItsHistory() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"enable_history":true}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        #expect(try await service.resourceMonitorHistoryEnabled())
        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.ResourceMonitor.Setting")
        #expect(parameters["method"] == "get")
    }

    /// Changing the setting is a mutation: a timeout must not replay it. The NAS may have
    /// applied it before answering, and a second attempt would overwrite a change made from
    /// DSM in the meantime.
    @Test func neverReplaysTheHistorySettingAfterATimeout() async throws {
        let stub = DSMRequestStub(results: [.timeout, .response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        do {
            try await service.setResourceMonitorHistory(enabled: true)
            Issue.record("Le changement de réglage aurait dû échouer après le délai d’attente.")
        } catch {
            let dsmError = try #require(error as? DSMError)
            guard case .network = dsmError else {
                Issue.record("Erreur inattendue : \(dsmError)")
                return
            }
        }
        #expect(await stub.requestCount == 1)
    }

    /// DSM expects the form checkbox under its own name, as a JSON boolean.
    @Test func sendsTheHistorySettingAsDSMNamesIt() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.setResourceMonitorHistory(enabled: false)

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.ResourceMonitor.Setting")
        #expect(parameters["method"] == "set")
        #expect(parameters["enable_history"] == "false")
    }

    /// Contract proven on the NAS: the target is sent in a single parameter named `service`,
    /// whatever the rule type. The web form's field names (`system`, `service_name`,
    /// `volume`) are not API parameters — sending them earns a refusal.
    @Test func sendsTheRuleTargetUnderTheSingleParameterDSMExpects() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.savePerformanceAlarmRule(
            PerformanceAlarmRuleDraft(kind: .system, resource: .memory, threshold: 80)
        )

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.ResourceMonitor.EventRule")
        #expect(parameters["method"] == "set")
        #expect(parameters["service"] == "\"general\"")
        #expect(parameters["type"] == "0")
        #expect(parameters["resource"] == "4")
        #expect(parameters["threshold"] == "80")
        #expect(parameters["system"] == nil)
        #expect(parameters["service_name"] == nil)
    }

    /// Verified on the NAS: `enable` is required when editing too, even though the web form
    /// hides the checkbox in that mode. Omitting it makes the request fail.
    @Test func alwaysSendsTheEnabledFlagEvenWhenEditing() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.savePerformanceAlarmRule(
            PerformanceAlarmRuleDraft(kind: .volume, resource: .diskActivity, target: "/volume1")
        )
        try await service.savePerformanceAlarmRule(
            PerformanceAlarmRuleDraft(
                ruleID: "3_/volume1_5_0",
                kind: .volume,
                resource: .diskActivity,
                isEnabled: false,
                target: "/volume1"
            )
        )

        let requests = await stub.requests
        let creation = try query(from: requests[0])
        let edition = try query(from: requests[1])
        #expect(creation["enable"] == "true")
        #expect(creation["id"] == nil)
        #expect(edition["enable"] == "false")
        // Decoded rather than compared raw: Foundation escapes the slash of a path when it
        // encodes a JSON string.
        #expect(try decode(String.self, from: edition["id"]) == "3_/volume1_5_0")
        #expect(try decode(String.self, from: edition["service"]) == "/volume1")
    }

    /// Rule identifiers are strings composed by the NAS, not numbers.
    @Test func togglesAndDeletesRulesByTheirStringIdentifiers() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.setPerformanceAlarmRules([(id: "0_general_4_0", enabled: false)])
        try await service.deletePerformanceAlarmRules(ids: ["0_general_4_0", "1_snmp.slice_0_1"])

        let requests = await stub.requests
        let toggle = try query(from: requests[0])
        #expect(toggle["method"] == "onoff")
        #expect(try decode([RuleState].self, from: toggle["id_list"])
            == [RuleState(id: "0_general_4_0", enable: false)])
        let removal = try query(from: requests[1])
        #expect(removal["method"] == "delete")
        #expect(try decode([String].self, from: removal["id_list"])
            == ["0_general_4_0", "1_snmp.slice_0_1"])
    }

    /// Saving a rule is a mutation: a timeout must not replay it. The NAS may have created it
    /// before answering, and the second attempt would then collide with the rule the first
    /// one just wrote.
    @Test func neverReplaysARuleSaveAfterATimeout() async throws {
        let stub = DSMRequestStub(results: [.timeout, .response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        do {
            try await service.savePerformanceAlarmRule(PerformanceAlarmRuleDraft())
            Issue.record("L’enregistrement aurait dû échouer après le délai d’attente.")
        } catch {
            let dsmError = try #require(error as? DSMError)
            guard case .network = dsmError else {
                Issue.record("Erreur inattendue : \(dsmError)")
                return
            }
        }
        #expect(await stub.requestCount == 1)
    }

    private struct RuleState: Decodable, Equatable {
        let id: String
        let enable: Bool
    }

    private struct WebReference: Decodable, Equatable {
        let did: String
        let who: String
        let descr: String
        let from: String
    }

    private struct ServiceReference: Decodable, Equatable {
        let pid: Int
        let type: String
        let who: String
        let from: String
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from parameter: String?) throws -> Value {
        let raw = try #require(parameter)
        return try JSONDecoder().decode(type, from: Data(raw.utf8))
    }

    private func makeService(stub: DSMRequestStub) -> DSMSystemService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Core.CurrentConnection": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Core.FileHandle": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.ResourceMonitor.Log": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.ResourceMonitor.Setting": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.ResourceMonitor.EventRule": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
        ])
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) }
        )
        transport.establishSession(LoginResult(sid: "session-id", did: nil, synotoken: nil))
        return DSMSystemService(transport: transport)
    }

    private func query(from request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
