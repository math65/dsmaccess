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
}
