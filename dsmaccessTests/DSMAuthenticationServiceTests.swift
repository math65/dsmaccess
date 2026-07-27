import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMAuthenticationServiceTests {
    @Test func logsInWithVersion7WhenTheNASSupportsIt() async throws {
        // DSM 7.4 bride les sessions v6 (402 sur la gestion des comptes) : le login doit
        // demander la version 7 dès qu'elle est disponible.
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
        // DSM soumet « session » au contrôle de privilèges d'application : un nom qui ne
        // correspond à aucune application installée passe pour un administrateur mais
        // refuse tout compte standard en 402.
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
        // 410 : DSM impose un nouveau mot de passe après réinitialisation par l'administrateur.
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

    private func makeService(stub: DSMRequestStub, maxVersion: Int) -> DSMAuthenticationService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.API.Auth": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: maxVersion
            ),
        ])
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) }
        )
        return DSMAuthenticationService(transport: transport)
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
