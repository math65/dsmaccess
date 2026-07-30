import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMAuthenticationServiceTests {
    @Test func logsInWithVersion7WhenTheNASSupportsIt() async throws {
        // DSM 7.4 restricts v6 sessions (402 on account management): login must ask for
        // version 7 as soon as it is available.
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"sid":"session-id","synotoken":"csrf-token"}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub, maxVersion: 7)

        let result = try await service.login(
            account: "martine",
            password: "secret",
            otpCode: nil,
            deviceID: nil,
            rememberDevice: false
        )

        #expect(result.sid == "session-id")
        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["api"] == "SYNO.API.Auth")
        #expect(parameters["version"] == "7")
        #expect(parameters["method"] == "login")
    }

    @Test func omitsTheSessionNameSoStandardAccountsCanLogIn() async throws {
        // DSM puts "session" through the application privilege check: a name that matches no
        // installed application goes through for an administrator but refuses any standard
        // account with a 402.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"sid":"session-id"}}"#.utf8)),
        ])
        let service = makeService(stub: stub, maxVersion: 7)

        _ = try await service.login(
            account: "martine",
            password: "secret",
            otpCode: nil,
            deviceID: nil,
            rememberDevice: false
        )

        let request = try #require(await stub.requests.first)
        #expect(try query(from: request)["session"] == nil)
    }

    @Test func omitsTheSessionNameOnLogout() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"sid":"session-id"}}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub, maxVersion: 7)
        _ = try await service.login(
            account: "martine",
            password: "secret",
            otpCode: nil,
            deviceID: nil,
            rememberDevice: false
        )

        await service.logout()

        let request = try #require(await stub.requests.last)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "logout")
        #expect(parameters["session"] == nil)
    }

    @Test func reportsThatThePasswordMustBeChanged() async throws {
        // 410: DSM requires a new password after an administrator reset.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":false,"error":{"code":410}}"#.utf8)),
        ])
        let service = makeService(stub: stub, maxVersion: 7)

        await #expect(throws: DSMError.passwordMustChange) {
            try await service.login(
                account: "martine",
                password: "secret",
                otpCode: nil,
                deviceID: nil,
                rememberDevice: false
            )
        }
    }

    @Test func fallsBackToTheHighestVersionOfOlderNAS() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"sid":"session-id"}}"#.utf8)),
        ])
        let service = makeService(stub: stub, maxVersion: 6)

        _ = try await service.login(
            account: "martine",
            password: "secret",
            otpCode: nil,
            deviceID: nil,
            rememberDevice: false
        )

        let request = try #require(await stub.requests.first)
        #expect(try query(from: request)["version"] == "6")
    }

    @Test func asksForApprovalWithoutSendingAnyPassword() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"request_id":"req-1","request_status":"waiting"}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub, maxVersion: 7, secureSignIn: true)

        let request = try await service.requestSecureSignIn(account: "martine", rememberDevice: false)

        #expect(request.requestID == "req-1")
        // The NAS does not always include the number: invent nothing when it is absent.
        #expect(request.verifyNumber == nil)
        let sent = try #require(await stub.requests.first)
        #expect(sent.httpMethod == "POST")
        let parameters = try body(from: sent)
        #expect(parameters["type"] == "authenticator")
        #expect(parameters["action"] == "get_status")
        #expect(parameters["application"] == "DSM")
        #expect(parameters["passwd"] == "")
        #expect(parameters["authenticator_token"] == "")
    }

    @Test func reportsAnExpiredApprovalRatherThanRejectedCredentials() async throws {
        // On this path, 400 signals an expired request. Turning it into "incorrect
        // credentials" would blame the user for a password mistake on a password they never
        // even typed.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":false,"error":{"code":400}}"#.utf8)),
        ])
        let service = makeService(stub: stub, maxVersion: 7, secureSignIn: true)

        await #expect(throws: SecureSignInExpired.self) {
            _ = try await service.requestSecureSignIn(account: "martine", rememberDevice: false)
        }
    }

    @Test func readsTheApprovalVerdictAndItsVerifyNumber() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"status":"waiting","verify_number":42}}"#.utf8)),
            .response(Data(
                #"{"success":true,"data":{"status":"approved","token":"approval-token","verify_number":42}}"#.utf8
            )),
            .response(Data(#"{"success":true,"data":{"status":"denied"}}"#.utf8)),
        ])
        let service = makeService(stub: stub, maxVersion: 7, secureSignIn: true)

        let waiting = try await service.secureSignInStatus(account: "martine", requestID: "req-1")
        let approved = try await service.secureSignInStatus(account: "martine", requestID: "req-1")
        let denied = try await service.secureSignInStatus(account: "martine", requestID: "req-1")

        #expect(waiting == .waiting(verifyNumber: 42))
        #expect(approved == .approved(token: "approval-token"))
        #expect(denied == .denied)
    }

    @Test func opensTheSessionWithTheApprovalToken() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"sid":"session-id","synotoken":"csrf-token"}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub, maxVersion: 7, secureSignIn: true)

        let result = try await service.completeSecureSignIn(
            account: "martine",
            requestID: "req-1",
            token: "approval-token",
            rememberDevice: false
        )

        #expect(result.sid == "session-id")
        let parameters = try body(from: try #require(await stub.requests.first))
        #expect(parameters["action"] == "approved")
        #expect(parameters["request_id"] == "req-1")
        #expect(parameters["authenticator_token"] == "approval-token")
        #expect(parameters["passwd"] == "")
    }

    @Test func hidesSecureSignInWhenTheNASDoesNotExposeIt() async throws {
        let stub = DSMRequestStub(results: [])

        #expect(!makeService(stub: stub, maxVersion: 7).supportsSecureSignIn)
        #expect(makeService(stub: stub, maxVersion: 7, secureSignIn: true).supportsSecureSignIn)
    }

    private func makeService(
        stub: DSMRequestStub,
        maxVersion: Int,
        secureSignIn: Bool = false
    ) -> DSMAuthenticationService {
        var capabilities = DSMCapabilities()
        var entries = [
            "SYNO.API.Auth": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: maxVersion
            ),
        ]
        if secureSignIn {
            entries["SYNO.SecureSignIn.Authenticator.Request"] = APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            )
        }
        capabilities.merge(entries)
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) }
        )
        return DSMAuthenticationService(transport: transport)
    }

    /// Secure SignIn login goes out as a POST: its parameters are in the body.
    private func body(from request: URLRequest) throws -> [String: String] {
        let data = try #require(request.httpBody)
        var components = URLComponents()
        components.percentEncodedQuery = String(decoding: data, as: UTF8.self)
        let items = try #require(components.queryItems)
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
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
