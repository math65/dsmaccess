import CryptoKit
import Foundation
import Testing
@testable import dsmaccess

struct QuickConnectResolverTests {
    @Test func validatesIdentifiersWithoutAcceptingHostSyntax() {
        #expect(QuickConnectResolver.isValid(id: "My-NAS-42"))
        #expect(!QuickConnectResolver.isValid(id: ""))
        #expect(!QuickConnectResolver.isValid(id: "42-NAS"))
        #expect(!QuickConnectResolver.isValid(id: "my-nas-"))
        #expect(!QuickConnectResolver.isValid(id: "my.nas"))
        #expect(!QuickConnectResolver.isValid(id: "ménas"))
        #expect(!QuickConnectResolver.isValid(id: String(repeating: "a", count: 64)))
    }

    @Test func resolvesAVerifiedSmartDNSRouteWithoutRequestingATunnel() async throws {
        let serverID = "my-nas"
        let host = "syn4-my-nas.direct.quickconnect.to"
        let stub = DSMRequestStub(results: [
            .response(serverInfo(serverID: serverID, smartDNSHost: host)),
            .response(ping(serverID: serverID)),
        ])
        let resolver = QuickConnectResolver(requestData: { try await stub.data(for: $0) })

        let route = try await resolver.resolve(id: serverID)

        #expect(route == QuickConnectRoute(
            endpoint: DSMEndpoint(useHTTPS: true, host: host, port: 5001),
            kind: .smartDNS
        ))
        let requests = await stub.requests
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString == "https://global.quickconnect.to/Serv.php")
        #expect(requests[1].url?.host == host)
        #expect(requests[1].url?.path == "/webman/pingpong.cgi")
        #expect(requests[1].url?.query == "action=cors&quickconnect=true")
        let command = try #require(requests[0].httpBody)
        let body = try JSONSerialization.jsonObject(with: command) as? [[String: Any]]
        #expect(body?.first?["command"] as? String == "get_server_info")
        #expect(body?.first?["id"] as? String == "mainapp_https")
        #expect(body?.first?["serverID"] as? String == serverID)
        #expect(body?.first?["account"] == nil)
        #expect(body?.first?["passwd"] == nil)
    }

    @Test func requestsAndVerifiesARelayWhenNoDirectRouteIsAvailable() async throws {
        let serverID = "my-nas"
        let relayHost = "my-nas.eu1.quickconnect.to"
        let stub = DSMRequestStub(results: [
            .response(serverInfo(serverID: serverID)),
            .response(serverInfo(serverID: serverID, relayReady: true)),
            .response(ping(serverID: serverID)),
        ])
        let resolver = QuickConnectResolver(requestData: { try await stub.data(for: $0) })

        let route = try await resolver.resolve(id: serverID)

        #expect(route == QuickConnectRoute(
            endpoint: DSMEndpoint(useHTTPS: true, host: relayHost, port: 443),
            kind: .relay
        ))
        let requests = await stub.requests
        #expect(requests.count == 3)
        #expect(requests[1].url?.absoluteString == "https://global.quickconnect.to/Serv.php")
        #expect(requests[2].url?.host == relayHost)
        let command = try #require(requests[1].httpBody)
        let body = try JSONSerialization.jsonObject(with: command) as? [[String: Any]]
        #expect(body?.first?["command"] as? String == "request_tunnel")
        #expect(body?.first?["stop_when_success"] as? Bool == true)
    }

    @Test func reportsAnUnknownIdentifierWithoutTryingDSM() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"[{"command":"get_server_info","errno":4,"suberrno":1,"version":1}]"#.utf8)),
        ])
        let resolver = QuickConnectResolver(requestData: { try await stub.data(for: $0) })

        await #expect(throws: QuickConnectError.unknownID) {
            try await resolver.resolve(id: "missing-nas")
        }
        #expect(await stub.requestCount == 1)
    }

    @Test func rejectsRoutesWhosePingAnswersForAnotherServer() async {
        // The link between the control response and the route goes through the pingpong:
        // a route that answers for another server is discarded, direct as well as relay.
        let host = "192-0-2-10.MY-NAS.direct.quickconnect.to"
        let stub = DSMRequestStub(results: [
            .response(serverInfo(serverID: "077000111", smartDNSHost: host)),
            .response(ping(serverID: "999999999")),
            .response(serverInfo(serverID: "077000111", relayReady: true)),
            .response(ping(serverID: "999999999")),
        ])
        let resolver = QuickConnectResolver(requestData: { try await stub.data(for: $0) })

        await #expect(throws: QuickConnectError.secureRouteUnavailable) {
            try await resolver.resolve(id: "my-nas")
        }
    }

    @Test func rejectsPingVerificationRedirectedToAnotherOrigin() async throws {
        let serverID = "my-nas"
        let host = "syn4-my-nas.direct.quickconnect.to"
        let redirectedURL = try #require(URL(string: "https://example.com/ping"))
        let stub = DSMRequestStub(results: [
            .response(serverInfo(serverID: serverID, smartDNSHost: host)),
            .responseAtURL(ping(serverID: serverID), redirectedURL),
            .response(Data(#"[{"errno":19}]"#.utf8)),
        ])
        let resolver = QuickConnectResolver(requestData: { try await stub.data(for: $0) })

        await #expect(throws: QuickConnectError.relayDisabled) {
            try await resolver.resolve(id: serverID)
        }
        #expect(await stub.requestCount == 3)
    }

    @Test func preservesCancellationFromTheConnectionTask() async {
        let resolver = QuickConnectResolver(requestData: { _ in
            throw CancellationError()
        })

        await #expect(throws: CancellationError.self) {
            try await resolver.resolve(id: "my-nas")
        }
    }

    @Test func acceptsTheNumericInternalServerIDReturnedByQuickConnect() async throws {
        // The real service returns a numeric internal identifier in `server.serverID`,
        // different from the alias requested, and the pingpong answers md5(internal id).
        let internalID = "077000111"
        let host = "192-0-2-10.MY-NAS.direct.quickconnect.to"
        let stub = DSMRequestStub(results: [
            .response(serverInfo(serverID: internalID, smartDNSHost: host)),
            .response(ping(serverID: internalID)),
        ])
        let resolver = QuickConnectResolver(requestData: { try await stub.data(for: $0) })

        let route = try await resolver.resolve(id: "my-nas")

        #expect(route == QuickConnectRoute(
            endpoint: DSMEndpoint(useHTTPS: true, host: host, port: 5001),
            kind: .smartDNS
        ))
    }

    @Test func prefersTheRelayHostProvidedByTheResponse() async throws {
        let internalID = "077000111"
        let relayDN = "synr-eu1.MY-NAS.direct.quickconnect.to"
        let relay = #", "relay_ip":"203.0.113.8", "relay_port":32047, "relay_dn":"\#(relayDN)""#
        let tunnel = Data(
            #"[{"command":"request_tunnel","errno":0,"server":{"serverID":"\#(internalID)","interface":[],"external":{"ip":"198.51.100.20"}},"service":{"port":5001,"ext_port":0,"pingpong":"CONNECTED"\#(relay)},"env":{"control_host":"global.quickconnect.to","relay_region":"eu1"},"version":1}]"#.utf8
        )
        let stub = DSMRequestStub(results: [
            .response(serverInfo(serverID: internalID)),
            .response(tunnel),
            .response(ping(serverID: internalID)),
        ])
        let resolver = QuickConnectResolver(requestData: { try await stub.data(for: $0) })

        let route = try await resolver.resolve(id: "my-nas")

        #expect(route == QuickConnectRoute(
            endpoint: DSMEndpoint(useHTTPS: true, host: relayDN, port: 443),
            kind: .relay
        ))
        let requests = await stub.requests
        #expect(requests[2].url?.host == relayDN)
    }

    private func serverInfo(
        serverID: String,
        smartDNSHost: String? = nil,
        relayReady: Bool = false
    ) -> Data {
        var smartDNS = ""
        if let smartDNSHost {
            smartDNS = #", "smartdns":{"host":"\#(smartDNSHost)"}"#
        }
        let relay = relayReady ? #", "relay_ip":"203.0.113.8", "relay_port":443"# : ""
        return Data(
            #"[{"command":"get_server_info","errno":0,"server":{"serverID":"\#(serverID)","interface":[{"ip":"192.0.2.10","ipv6":[]}],"external":{"ip":"198.51.100.20"}},"service":{"port":5001,"ext_port":0,"pingpong":"CONNECTED"\#(relay)},"env":{"control_host":"global.quickconnect.to","relay_region":"eu1"}\#(smartDNS),"version":1}]"#.utf8
        )
    }

    private func ping(serverID: String) -> Data {
        let digest = Insecure.MD5.hash(data: Data(serverID.utf8))
            .map { byte in
                let hexadecimal = String(byte, radix: 16)
                return byte < 16 ? "0\(hexadecimal)" : hexadecimal
            }
            .joined()
        return Data(#"{"ezid":"\#(digest)"}"#.utf8)
    }
}
