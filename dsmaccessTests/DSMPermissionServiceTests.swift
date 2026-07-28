import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMPermissionServiceTests {
    @Test func readsSharePermissionsOfAnAccount() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"shares":[{"name":"photo","share_path":"/volume1/photo","inherit":"ro","is_readonly":false,"is_writable":false,"is_deny":false,"is_custom":false},{"name":"docker","share_path":"/volume1/docker","inherit":"-","is_readonly":false,"is_writable":true,"is_deny":false,"is_custom":true}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let permissions = try await service.sharePermissions(for: .user("martine"))

        #expect(permissions.map(\.name) == ["photo", "docker"])
        #expect(permissions[0].inherited == .readOnly)
        #expect(permissions[0].granted == nil)
        #expect(permissions[1].inherited == nil)
        #expect(permissions[1].granted == .readWrite)
        #expect(permissions[1].isCustom)

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["api"] == "SYNO.Core.Share.Permission")
        #expect(parameters["method"] == "list_by_user")
        #expect(parameters["name"] == #""martine""#)
        // Sans user_group_type, DSM répond 403 au lieu de choisir un défaut.
        #expect(parameters["user_group_type"] == #""local_user""#)
    }

    @Test func sendsOnlyTheSharesItWasGiven() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.setSharePermissions(
            [
                DSMSharePermission(name: "photo", granted: .readOnly),
                DSMSharePermission(name: "docker", granted: nil, isCustom: true),
            ],
            for: .user("martine")
        )

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "set_by_user_group")
        #expect(parameters["user_group_type"] == #""local_user""#)
        let payload = try #require(parameters["permissions"])
        let sent = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [[String: Any]]
        let entries = try #require(sent)
        #expect(entries.count == 2)
        #expect(entries[0]["name"] as? String == "photo")
        #expect(entries[0]["is_readonly"] as? Bool == true)
        #expect(entries[0]["is_writable"] as? Bool == false)
        #expect(entries[0]["is_deny"] as? Bool == false)
        // Les permissions détaillées de File Station doivent survivre à un changement de niveau.
        #expect(entries[1]["is_custom"] as? Bool == true)
        #expect(entries[1]["is_readonly"] as? Bool == false)
    }

    @Test func readsSharePermissionsOfAGroup() async throws {
        // Un groupe n'hérite de rien : DSM change de méthode et omet « inherit ».
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"shares":[{"name":"photo","share_path":"/volume1/photo","is_readonly":true,"is_writable":false,"is_deny":false,"is_custom":false}],"total":1}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let permissions = try await service.sharePermissions(for: .group("famille"))

        #expect(permissions.map(\.granted) == [.readOnly])
        #expect(permissions[0].inherited == nil)

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "list_by_group")
        #expect(parameters["name"] == #""famille""#)
        #expect(parameters["user_group_type"] == #""local_group""#)
    }

    @Test func writesGroupPermissionsThroughTheSharedMethod() async throws {
        // La lecture a deux méthodes, l'écriture une seule : c'est user_group_type qui
        // distingue le groupe du compte.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.setSharePermissions(
            [DSMSharePermission(name: "photo", granted: .noAccess)],
            for: .group("famille")
        )

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "set_by_user_group")
        #expect(parameters["name"] == #""famille""#)
        #expect(parameters["user_group_type"] == #""local_group""#)
    }

    @Test func sendsNothingWhenNoShareChanged() async throws {
        let stub = DSMRequestStub(results: [])
        let service = makeService(stub: stub)

        try await service.setSharePermissions([], for: .group("famille"))

        #expect(await stub.requests.isEmpty)
    }

    @Test func appliesTheConflictRuleAnnouncedByDSM() {
        // DSM résout un conflit compte/groupe dans l'ordre NA > RW > RO.
        let denied = DSMSharePermission(name: "photo", inherited: .noAccess, granted: .readWrite)
        #expect(denied.effective == .noAccess)

        let promoted = DSMSharePermission(name: "photo", inherited: .readOnly, granted: .readWrite)
        #expect(promoted.effective == .readWrite)

        let inheritedOnly = DSMSharePermission(name: "photo", inherited: .readOnly, granted: nil)
        #expect(inheritedOnly.effective == .readOnly)

        let nothing = DSMSharePermission(name: "photo")
        #expect(nothing.effective == .noAccess)
    }

    @Test func mergesTheApplicationCatalogWithTheRulesOfTheHolder() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"applications":[{"app_id":"SYNO.Desktop","name":"DSM","grant_by_default":true},{"app_id":"SYNO.Finder.Application","name":"Universal Search","grant_by_default":false},{"app_id":"SYNO.FTP","name":"FTP","grant_by_default":true}]}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"rules":[{"app_id":"SYNO.Desktop","allow_ip":[],"deny_ip":["0.0.0.0"],"entity_name":"martine","entity_type":"user"},{"app_id":"SYNO.FTP","allow_ip":["192.168.1.10"],"deny_ip":[],"entity_name":"martine","entity_type":"user"}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let privileges = try await service.applicationPrivileges(for: .user("martine"))

        #expect(privileges.map(\.appID) == ["SYNO.Desktop", "SYNO.Finder.Application", "SYNO.FTP"])
        #expect(privileges[0].decision == .deny)
        // Sans règle, l'application relève du défaut : ce n'est pas un refus.
        #expect(privileges[1].decision == nil)
        #expect(!privileges[1].isGrantedByDefault)
        // Une règle limitée à une adresse ne doit pas être réécrite en « toutes ».
        #expect(privileges[2].decision == .allow)
        #expect(privileges[2].restrictsAddresses)
        #expect(!privileges[0].restrictsAddresses)

        let requests = await stub.requests
        #expect(requests.count == 2)
        #expect(try query(from: requests[0])["api"] == "SYNO.Core.AppPriv.App")
        let ruleQuery = try query(from: requests[1])
        #expect(ruleQuery["api"] == "SYNO.Core.AppPriv.Rule")
        #expect(ruleQuery["method"] == "get")
        #expect(ruleQuery["entity_type"] == #""user""#)
        #expect(ruleQuery["entity_name"] == #""martine""#)
    }

    @Test func deletesTheRuleWhenAnApplicationReturnsToItsDefault() async throws {
        // DSM n'a pas de valeur « aucune règle » : seul le retrait de la règle rend le défaut.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.setApplicationPrivileges(
            [
                DSMApplicationPrivilege(
                    appID: "SYNO.Desktop",
                    name: "DSM",
                    isGrantedByDefault: true,
                    decision: nil,
                    restrictsAddresses: false
                ),
                DSMApplicationPrivilege(
                    appID: "SYNO.FTP",
                    name: "FTP",
                    isGrantedByDefault: true,
                    decision: .deny,
                    restrictsAddresses: false
                ),
            ],
            for: .group("famille")
        )

        let requests = await stub.requests
        #expect(requests.count == 2)
        let removal = try query(from: requests[0])
        #expect(removal["method"] == "delete")
        let removed = try JSONSerialization.jsonObject(with: Data(try #require(removal["rules"]).utf8))
        let removedEntries = try #require(removed as? [[String: Any]])
        #expect(removedEntries.count == 1)
        #expect(removedEntries[0]["app_id"] as? String == "SYNO.Desktop")
        #expect(removedEntries[0]["entity_type"] as? String == "group")

        let change = try query(from: requests[1])
        #expect(change["method"] == "set")
        let sent = try JSONSerialization.jsonObject(with: Data(try #require(change["rules"]).utf8))
        let entries = try #require(sent as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["app_id"] as? String == "SYNO.FTP")
        #expect(entries[0]["deny_ip"] as? [String] == ["0.0.0.0"])
        #expect(entries[0]["allow_ip"] as? [String] == [])
    }

    private func makeService(stub: DSMRequestStub) -> DSMPermissionService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Core.Share.Permission": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Core.AppPriv.App": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 3,
                requestFormat: "JSON"
            ),
            "SYNO.Core.AppPriv.Rule": APIInfoEntry(
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
        return DSMPermissionService(transport: transport)
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
