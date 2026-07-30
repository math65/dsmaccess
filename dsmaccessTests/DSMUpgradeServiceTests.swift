import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMUpgradeServiceTests {
    @Test func sendsThePatchWithRoutingInTheQueryAndTargetInTheBody() async throws {
        let patch = try makePatchFile(named: "DSM_DS920+_90080.pat", bytes: 2048)
        defer { try? FileManager.default.removeItem(at: patch) }
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.uploadPatch(at: patch)

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        // Put in the multipart body, these fields make DSM answer 101.
        #expect(parameters["api"] == "SYNO.Core.Upgrade.Patch")
        #expect(parameters["method"] == "upload")
        #expect(parameters["_sid"] == "session-id")
        #expect(request.httpMethod == "POST")
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
    }

    @Test func refusesAFileThatIsNotAPatch() async throws {
        let archive = try makePatchFile(named: "paquet.spk", bytes: 512)
        defer { try? FileManager.default.removeItem(at: archive) }
        let stub = DSMRequestStub(results: [])
        let service = makeService(stub: stub)

        await #expect(throws: (any Error).self) {
            try await service.uploadPatch(at: archive)
        }
        #expect(await stub.requests.isEmpty)
    }

    @Test func startsTheUpgradeWithoutReplayingIt() async throws {
        // A system upgrade is never replayed after a timeout.
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.start()

        let requests = await stub.requests
        #expect(requests.count == 1)
        let parameters = try query(from: requests[0])
        #expect(parameters["api"] == "SYNO.Core.Upgrade")
        #expect(parameters["method"] == "start")
    }

    @Test func readsTheAnnouncedUnsupportedPackages() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"unsupported_packages":["PHP 7.4","Node.js v18"]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let result = try await service.preCheck()

        #expect(result.isUnderstood)
        #expect(result.unsupportedPackages == ["Node.js v18", "PHP 7.4"])
    }

    @Test func acceptsPackagesWrittenAsObjects() async throws {
        // The exact shape of the response could not be measured: both spellings are accepted.
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"break_pkgs":[{"display_name":"PHP 7.4"},{"name":"MariaDB"}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let result = try await service.preCheck()

        #expect(result.isUnderstood)
        #expect(result.unsupportedPackages == ["MariaDB", "PHP 7.4"])
    }

    @Test func survivesAPreCheckItCannotRead() async throws {
        // An unknown format must not interrupt the operation, but must report itself as not
        // understood so the screen sends the user back to DSM.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"quelque_chose":42}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let result = try await service.preCheck()

        #expect(!result.isUnderstood)
        #expect(result.unsupportedPackages.isEmpty)
    }

    @Test func readsTheInstallationProgress() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"progress":42,"status":"processing"}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let progression = try await service.progress()

        #expect(progression.percentage == 42)
        #expect(!progression.isFinished)
    }

    @Test func clampsAnOutOfRangeProgress() throws {
        let dépassement = try JSONDecoder().decode(
            DSMUpgradeProgress.self,
            from: Data(#"{"progress":150,"finished":true}"#.utf8)
        )
        #expect(dépassement.percentage == 100)
        #expect(dépassement.isFinished)
    }

    @Test func readsTheBootStateOfTheHost() throws {
        // ⚠️ boot_done turns true before DSM accepts a connection: this flag says the host
        // answers, not that the upgrade is finished.
        let démarré = try JSONDecoder().decode(
            DSMBootState.self,
            from: Data(#"{"boot_done":true,"disk_hibernation":false,"success":true}"#.utf8)
        )
        #expect(démarré.isBootDone)
        let enCours = try JSONDecoder().decode(
            DSMBootState.self,
            from: Data(#"{"boot_done":false,"success":true}"#.utf8)
        )
        #expect(!enCours.isBootDone)
    }

    private func makePatchFile(named name: String, bytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let fichier = url.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: fichier)
        return fichier
    }

    private func makeService(stub: DSMRequestStub) -> DSMUpgradeService {
        var capabilities = DSMCapabilities()
        for name in ["SYNO.Core.Upgrade", "SYNO.Core.Upgrade.Patch", "SYNO.Core.Upgrade.PreCheck"] {
            capabilities.merge([
                name: APIInfoEntry(
                    path: "entry.cgi",
                    minVersion: 1,
                    maxVersion: 1,
                    requestFormat: "JSON"
                ),
            ])
        }
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) },
            // Without this injection, the upload would go out to the real network and the test
            // would block until the 900 s timeout meant for a file of several hundred megabytes.
            uploadFile: { try await stub.upload(for: $0, fromFile: $1) }
        )
        transport.establishSession(LoginResult(sid: "session-id", did: nil, synotoken: nil))
        return DSMUpgradeService(transport: transport)
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
