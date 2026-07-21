import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMCapabilitiesTests {
    @Test func resolvesHighestCompatibleVersion() throws {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Example": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 2,
                maxVersion: 5,
                requestFormat: "JSON"
            ),
        ])

        let resolved = try capabilities.resolve(
            DSMAPI("SYNO.Example", preferredVersion: 4, minimumVersion: 3)
        )

        #expect(resolved.path == "entry.cgi")
        #expect(resolved.version == 4)
        #expect(resolved.requestFormat == "JSON")
    }

    @Test func capsPreferredVersionAtServerMaximum() throws {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Example": APIInfoEntry(path: "example.cgi", minVersion: 1, maxVersion: 3),
        ])

        let resolved = try capabilities.resolve(
            DSMAPI("SYNO.Example", preferredVersion: 6)
        )

        #expect(resolved.version == 3)
    }

    @Test func rejectsUnsupportedVersionRange() {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Example": APIInfoEntry(path: "example.cgi", minVersion: 1, maxVersion: 2),
        ])

        #expect(throws: DSMError.unsupportedAPIVersion("SYNO.Example")) {
            try capabilities.resolve(DSMAPI("SYNO.Example", preferredVersion: 2, minimumVersion: 3))
        }
    }

    @Test func reportsExactAndPrefixedCapabilities() {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.DownloadStation.Task": APIInfoEntry(
                path: "DownloadStation/task.cgi",
                minVersion: 1,
                maxVersion: 3
            ),
        ])

        #expect(capabilities.supports("SYNO.DownloadStation.Task"))
        #expect(capabilities.supports(prefix: "SYNO.DownloadStation"))
        #expect(!capabilities.supports("SYNO.DownloadStation.Statistic"))
    }

    @Test func centralizesSessionAuthenticationAndRequestFormat() async throws {
        let endpoint = DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001)
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Example": APIInfoEntry(
                path: "example.cgi",
                minVersion: 1,
                maxVersion: 2,
                requestFormat: "JSON"
            ),
        ])
        let transport = DSMTransport(
            endpoint: endpoint,
            session: .shared,
            capabilities: capabilities
        )
        transport.establishSession(
            LoginResult(sid: "session-id", did: nil, synotoken: "csrf-token")
        )

        let url = try await transport.makeURL(
            api: DSMAPI("SYNO.Example", preferredVersion: 2),
            method: "update",
            parameters: [
                "path": .string("/Photos/Été 2026"),
                "enabled": .boolean(true),
                "limit": .integer(12),
            ]
        )
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(items.contains(URLQueryItem(name: "_sid", value: "session-id")))
        #expect(items.contains(URLQueryItem(name: "SynoToken", value: "csrf-token")))
        let encodedPath = try #require(items.first { $0.name == "path" }?.value)
        let decodedPath = try JSONDecoder().decode(String.self, from: Data(encodedPath.utf8))
        #expect(decodedPath == "/Photos/Été 2026")
        #expect(items.contains(URLQueryItem(name: "enabled", value: "true")))
        #expect(items.contains(URLQueryItem(name: "limit", value: "12")))
    }

    @Test func encodesFormParametersWithoutJSONQuoting() throws {
        #expect(try DSMParameter.string("dossier été").encoded(for: nil) == "dossier été")
        #expect(try DSMParameter.boolean(false).encoded(for: "FORM") == "false")
        #expect(try DSMParameter.integer(-1).encoded(for: "FORM") == "-1")
        #expect(try DSMParameter.json(["a", "b"]).encoded(for: "FORM") == "[\"a\",\"b\"]")
    }

    @Test func constructsEncodedDiscoveredRoutes() throws {
        let endpoint = DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001)
        let transport = DSMTransport(endpoint: endpoint, session: .shared)

        let url = try transport.makeURL(
            path: "FileStation/file_share.cgi",
            parameters: ["path": "/Photos/Été 2026", "method": "list"]
        )
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "nas.local")
        #expect(components.port == 5001)
        #expect(components.path == "/webapi/FileStation/file_share.cgi")
        #expect(components.queryItems?.contains(URLQueryItem(name: "path", value: "/Photos/Été 2026")) == true)
    }

    @Test func gatesEveryModuleByDiscoveredCapabilities() {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.DSM.Info": APIInfoEntry(path: "entry.cgi", minVersion: 1, maxVersion: 2),
            "SYNO.Core.FileServ.SMB": APIInfoEntry(path: "entry.cgi", minVersion: 1, maxVersion: 3),
            "SYNO.Core.Network": APIInfoEntry(path: "entry.cgi", minVersion: 1, maxVersion: 2),
        ])

        #expect(AppModule.systemInfo.isAvailable(in: capabilities))
        #expect(AppModule.fileServices.isAvailable(in: capabilities))
        #expect(AppModule.controlPanel.isAvailable(in: capabilities))
        #expect(!AppModule.storage.isAvailable(in: capabilities))
        #expect(!AppModule.files.isAvailable(in: capabilities))
        #expect(!AppModule.shares.isAvailable(in: capabilities))
        #expect(!AppModule.packages.isAvailable(in: capabilities))
    }

    @Test func decodesNetworkIdentityAndGatewayInterface() throws {
        let data = Data(
            #"""
            {
              "server_name": "DiskStation",
              "gateway": "192.168.1.1",
              "dns_primary": "1.1.1.1",
              "dns_secondary": "9.9.9.9",
              "dns_manual": true,
              "v6gateway": "fe80::1",
              "enable_windomain": false,
              "gateway_info": {
                "ifname": "eth0",
                "ip": "192.168.1.20",
                "mask": "255.255.255.0",
                "status": "connected",
                "type": "lan",
                "use_dhcp": false
              }
            }
            """#.utf8
        )

        let info = try JSONDecoder().decode(NetworkInfo.self, from: data)

        #expect(info.serverName == "DiskStation")
        #expect(info.gateway == "192.168.1.1")
        #expect(info.dnsPrimary == "1.1.1.1")
        #expect(info.dnsManual == true)
        #expect(info.gatewayInfo?.ifname == "eth0")
        #expect(info.gatewayInfo?.ip == "192.168.1.20")
        #expect(info.gatewayInfo?.useDhcp == false)
    }

    @Test func mapsExpiredSessionsFromEveryResponsePath() {
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared
        )

        #expect(transport.error(from: DSMErrorBody(code: 106)) == .sessionExpired)
        #expect(transport.error(from: DSMErrorBody(code: 107)) == .sessionExpired)
        #expect(transport.error(from: DSMErrorBody(code: 119)) == .sessionExpired)
        #expect(transport.error(from: DSMErrorBody(code: 105)) == .permissionDenied)
    }

    @Test func decodesASingleDSMErrorDetailDictionary() async throws {
        let data = Data(
            #"{"success":false,"error":{"code":120,"errors":{"name":"extra_values","reason":"type"}}}"#.utf8
        )

        let response = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
        let body = try #require(response.error)
        let detail = try #require(body.errors?.first)

        #expect(body.code == 120)
        #expect(detail.code == nil)
        #expect(detail.name == "extra_values")
        #expect(detail.reason == "type")

        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared
        )
        #expect(transport.error(from: body) == .apiError(code: 120))
    }
}
