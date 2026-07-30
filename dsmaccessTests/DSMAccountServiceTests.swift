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
        // DSM ignores "members" in additional: only ask for what is honoured.
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
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.createUser(
            DSMUserDraft(
                name: "martine",
                password: "secret",
                description: "Compte invité",
                email: "",
                groups: ["users", "photo"]
            )
        )

        let requests = await stub.requests
        #expect(requests.count == 3)
        let creation = try query(from: requests[0])
        #expect(creation["api"] == "SYNO.Core.User")
        #expect(creation["method"] == "create")
        #expect(creation["name"] == #""martine""#)
        #expect(creation["password"] == #""secret""#)
        #expect(creation["_sid"] == "session-id")
        // DSM 7.4 ignores "group" here: sending it would suggest the membership is
        // applied when it is not.
        #expect(creation["group"] == nil)

        let firstGroup = try query(from: requests[1])
        #expect(firstGroup["api"] == "SYNO.Core.Group.Member")
        #expect(firstGroup["method"] == "change")
        #expect(firstGroup["group"] == #""users""#)
        #expect(firstGroup["add_member"] == #"["martine"]"#)
        let secondGroup = try query(from: requests[2])
        #expect(secondGroup["group"] == #""photo""#)
    }

    @Test func createsNoGroupCallWhenTheDraftHasNoGroup() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"name":"martine","uid":1031}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.createUser(
            DSMUserDraft(name: "martine", password: "secret", description: "", email: "", groups: [])
        )

        #expect(await stub.requests.count == 1)
    }

    @Test func reportsAnAccountCreatedWithoutItsGroups() async throws {
        // The account exists as of the first call: presenting a plain failure would push the
        // user to resubmit the form, which would then hit a name already taken.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"name":"martine","uid":1031}}"#.utf8)),
            .response(Data(#"{"success":false,"error":{"code":402}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        await #expect(throws: DSMError.userCreatedWithoutGroups(name: "martine")) {
            try await service.createUser(
                DSMUserDraft(
                    name: "martine",
                    password: "secret",
                    description: "",
                    email: "",
                    groups: ["users"]
                )
            )
        }
        #expect(await stub.requests.count == 2)
    }

    @Test func addsAndRemovesGroupsOfAnExistingAccount() async throws {
        // DSM only changes one group at a time: it is the group that carries its members.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.setMemberships(of: "martine", joining: ["photo"], leaving: ["users"])

        let requests = await stub.requests
        #expect(requests.count == 2)
        let joined = try query(from: requests[0])
        #expect(joined["api"] == "SYNO.Core.Group.Member")
        #expect(joined["method"] == "change")
        #expect(joined["group"] == #""photo""#)
        #expect(joined["add_member"] == #"["martine"]"#)
        #expect(joined["remove_member"] == nil)
        let left = try query(from: requests[1])
        #expect(left["group"] == #""users""#)
        #expect(left["remove_member"] == #"["martine"]"#)
        #expect(left["add_member"] == nil)
    }

    @Test func reportsAPasswordRefusedByTheNASPolicy() async throws {
        // 3121: the password does not meet the NAS strength rules. Without this
        // mapping, the app only shows a raw code and creation looks broken.
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
        // DSM keeps "min_length" even when disabled: do not announce an inactive rule.
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
