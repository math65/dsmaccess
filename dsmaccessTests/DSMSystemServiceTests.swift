import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMSystemServiceTests {
    /// Contrat relevé sur DSM 7.4 : `kick_connection` ne prend pas d'identifiant de session.
    /// Il attend deux listes, et le tri entre les deux dépend du protocole. Une session web
    /// rangée dans `service_conn` — ou l'inverse — ne coupe rien tout en répondant vrai.
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

    /// Le client web envoie toujours les deux paramètres. En omettre un vide exposerait au
    /// risque que DSM lise la liste restante comme portant sur tous les protocoles.
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

    /// Couper une session est une mutation : un délai d'attente ne doit pas la rejouer. Le NAS
    /// peut avoir fermé les sessions avant de répondre, et une seconde tentative couperait
    /// alors des sessions rouvertes entre-temps.
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

    /// Une erreur DSM doit remonter comme telle : un échec présenté en succès laisserait
    /// croire qu'une session a été fermée alors qu'elle reste ouverte.
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
