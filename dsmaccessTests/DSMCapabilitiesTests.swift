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

    @Test func centralizesSessionAuthentication() throws {
        let endpoint = DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001)
        let transport = DSMTransport(endpoint: endpoint, session: .shared)
        transport.establishSession(
            LoginResult(sid: "session-id", did: nil, synotoken: "csrf-token")
        )

        let parameters = try transport.authenticatedParameters()

        #expect(parameters["_sid"] == "session-id")
        #expect(parameters["SynoToken"] == "csrf-token")
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
