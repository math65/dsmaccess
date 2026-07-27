import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMAccountServiceTests {
    @Test func fetchesGroupMembersThroughTheDedicatedAPI() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"groups":[{"name":"administrators"},{"name":"users"}],"offset":0,"total":2}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"offset":0,"total":2,"users":[{"name":"admin","uid":1024},{"name":"math65","uid":1026}]}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"offset":0,"total":1,"users":[{"name":"math65","uid":1026}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let groups = try await service.groups()

        #expect(groups.map(\.name) == ["administrators", "users"])
        #expect(groups.first?.members == ["admin", "math65"])
        #expect(groups.last?.members == ["math65"])

        let requests = await stub.requests
        #expect(requests.count == 3)
        let listParameters = try query(from: requests[0])
        // DSM ignore « members » dans l'additional : ne demander que ce qui est honoré.
        #expect(listParameters["additional"] == #"["description"]"#)
        let firstMembers = try query(from: requests[1])
        #expect(firstMembers["api"] == "SYNO.Core.Group.Member")
        #expect(firstMembers["method"] == "list")
        #expect(firstMembers["group"] == #""administrators""#)
        let secondMembers = try query(from: requests[2])
        #expect(secondMembers["group"] == #""users""#)
    }

    @Test func groupLoadingFailsWhenMembersCannotBeRead() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"groups":[{"name":"administrators"}],"offset":0,"total":1}}"#.utf8
            )),
            .response(Data(#"{"success":false,"error":{"code":105}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        await #expect(throws: DSMError.permissionDenied) {
            _ = try await service.groups()
        }
    }

    @Test func sendsTheVerifiedUserCreationContract() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"name":"martine","uid":1031}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.createUser(
            DSMUserDraft(
                name: "martine",
                password: "secret",
                description: "Compte invité",
                email: "",
                groups: ["users"]
            )
        )

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["api"] == "SYNO.Core.User")
        #expect(parameters["method"] == "create")
        #expect(parameters["name"] == #""martine""#)
        #expect(parameters["password"] == #""secret""#)
        #expect(parameters["group"] == #"["users"]"#)
        #expect(parameters["_sid"] == "session-id")
    }

    @Test func reportsAPasswordRefusedByTheNASPolicy() async throws {
        // 3121 : le mot de passe ne satisfait pas les règles de force du NAS. Sans ce
        // mapping, l'app n'affiche qu'un code brut et la création paraît cassée.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":false,"error":{"code":3121}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        await #expect(throws: DSMError.weakPassword) {
            try await service.createUser(
                DSMUserDraft(
                    name: "martine",
                    password: "abc",
                    description: "",
                    email: "",
                    groups: []
                )
            )
        }
    }

    @Test func readsTheActivePasswordRules() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"password_must_change":true,"strong_password":{"exclude_common_password":false,"exclude_username":true,"included_numeric_char":true,"included_special_char":false,"min_length":8,"min_length_enable":true,"mixed_case":true}}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let policy = try await service.passwordPolicy()

        #expect(policy.minimumLength == 8)
        #expect(policy.requiresMixedCase)
        #expect(policy.requiresDigit)
        #expect(!policy.requiresSpecialCharacter)
        #expect(policy.excludesUserName)
        #expect(policy.requirements.count == 4)

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["api"] == "SYNO.Core.User.PasswordPolicy")
        #expect(parameters["method"] == "get")
    }

    @Test func ignoresTheMinimumLengthWhenTheRuleIsOff() async throws {
        // DSM conserve « min_length » même désactivé : ne pas annoncer une règle inactive.
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"strong_password":{"min_length":8,"min_length_enable":false,"mixed_case":false,"included_numeric_char":false}}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let policy = try await service.passwordPolicy()

        #expect(policy.minimumLength == nil)
        #expect(!policy.hasRequirements)
    }

    private func makeService(stub: DSMRequestStub) -> DSMAccountService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Core.User": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Core.Group": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Core.Group.Member": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Core.User.PasswordPolicy": APIInfoEntry(
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
        return DSMAccountService(transport: transport)
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
