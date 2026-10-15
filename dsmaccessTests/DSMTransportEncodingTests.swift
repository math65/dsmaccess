import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMTransportEncodingTests {
    // DSM reads a bare "+" as a space (measured on DSM 7.4.1): it must leave as %2B.

    @Test func encodesAPlusInTheQueryString() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let transport = makeTransport(stub: stub)

        try await transport.perform(
            api: DSMAPI("SYNO.Example"),
            method: "set",
            parameters: ["passwd": .string("a+b c"), "path": .string("/home/x+y")],
            authenticated: false
        )

        let request = try #require(await stub.requests.first)
        let query = try #require(request.url?.query(percentEncoded: true))
        #expect(!query.contains("+"))
        #expect(query.contains("passwd=a%2Bb%20c"))
        #expect(query.contains("path=/home/x%2By"))
    }

    @Test func encodesAPlusInAFormBody() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let transport = makeTransport(stub: stub)

        try await transport.perform(
            api: DSMAPI("SYNO.Example"),
            method: "set",
            parameters: ["passwd": .string("a+b")],
            authenticated: false,
            httpMethod: .post
        )

        let request = try #require(await stub.requests.first)
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(!body.contains("+"))
        #expect(body.contains("passwd=a%2Bb"))
    }

    @Test func aPlusSurvivesTheRoundTrip() throws {
        let encoded = try #require(DSMTransport.formEncoded(["passwd": "1+1=2 & more"]))
        var components = URLComponents()
        components.percentEncodedQuery = encoded
        #expect(components.queryItems?.first?.value == "1+1=2 & more")
    }

    private func makeTransport(stub: DSMRequestStub) -> DSMTransport {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Example": APIInfoEntry(path: "entry.cgi", minVersion: 1, maxVersion: 1),
        ])
        return DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) }
        )
    }
}
