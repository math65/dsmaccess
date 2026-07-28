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

    private func makeService(stub: DSMRequestStub) -> DSMPermissionService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Core.Share.Permission": APIInfoEntry(
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
