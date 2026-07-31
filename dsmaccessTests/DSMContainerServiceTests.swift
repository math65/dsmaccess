import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMContainerServiceTests {
    @Test func loadsDSM74ResourcesFromTheResourceAPI() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"containers":[{"id":"container-id","name":"web","image":"nginx:latest","status":"running","up_time":90061}]}}"#.utf8
            )),
            .response(Data(
                #"{"success":true,"data":{"resources":[{"name":"web","cpu":2.5,"memory":67108864}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let containers = try await service.containers()

        let container = try #require(containers.first)
        #expect(container.cpuPercent == 2.5)
        #expect(container.memoryBytes == 67_108_864)
        #expect(container.uptimeSeconds == 90_061)

        let requests = await stub.requests
        #expect(requests.count == 2)
        #expect(try query(from: requests[0])["type"] == "all")
        #expect(try query(from: requests[1])["api"] == "SYNO.Docker.Container.Resource")
        #expect(try query(from: requests[1])["method"] == "get")
    }

    @Test func getsCompleteContainerLogRequestAndDecodesDSM74Rows() async throws {
        let response = Data(
            #"{"success":true,"data":{"logs":[{"created":"2025-06-15T10:38:55.869358659Z","docid":"42","stream":"stderr","text":"Starting server"}]}}"#.utf8
        )
        let stub = DSMRequestStub(results: [.response(response)])
        let service = makeService(stub: stub)

        let logs = try await service.logs(name: "web", limit: 300)

        let entry = try #require(logs.first)
        #expect(entry.id == "42")
        #expect(entry.timestamp == "2025-06-15T10:38:55.869358659Z")
        #expect(entry.stream == "stderr")
        #expect(entry.message == "Starting server")

        let requests = await stub.requests
        let request = try #require(requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        let parameters = try query(from: request)
        #expect(parameters["api"] == "SYNO.Docker.Container.Log")
        #expect(parameters["method"] == "get")
        #expect(parameters["name"] == #""web""#)
        #expect(parameters["from"] == #""""#)
        #expect(parameters["to"] == #""""#)
        #expect(parameters["level"] == #""""#)
        #expect(parameters["keyword"] == #""""#)
        #expect(parameters["sort_by"] == #""time""#)
        #expect(parameters["sort_dir"] == #""DESC""#)
        #expect(parameters["offset"] == "0")
        #expect(parameters["limit"] == "300")
    }

    @Test func decodesProjectsKeyedByIdentifierAndParsesDates() async throws {
        // `list` keys its projects by identifier; timestamps carry fractional seconds.
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"79a1":{"id":"79a1","name":"radio","path":"/volume1/docker/radio","status":"RUNNING","containerIds":["c1"],"created_at":"2025-04-08T20:41:48.391487Z","updated_at":"2025-04-08T20:41:48.391487Z","is_package":false,"enable_service_portal":false,"service_portal_name":"","service_portal_port":0,"service_portal_protocol":"","services":null,"share_path":"/docker/radio","state":"","version":2}}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let projects = try await service.projects()

        let project = try #require(projects.first)
        #expect(project.id == "79a1")
        #expect(project.status == .running)
        #expect(project.containerCount == 1)
        #expect(project.createdAt != nil)
        #expect(project.content == nil)
    }

    @Test func projectActionParsesStreamOutputAndExitCode() async throws {
        // `*_stream` methods answer with raw text, not the JSON envelope.
        let stub = DSMRequestStub(results: [
            .response(Data(
                " Container web-1  Stopping\n Container web-1  Stopped\nExit Code: 0\n".utf8
            )),
        ])
        let service = makeService(stub: stub)

        let result = try await service.performProjectAction(.stop, projectID: "79a1")

        #expect(result.succeeded)
        #expect(result.exitCode == 0)
        #expect(result.lines == ["Container web-1  Stopping", "Container web-1  Stopped"])
        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "stop_stream")
        #expect(parameters["id"] == #""79a1""#)
    }

    @Test func projectActionSurfacesEnvelopeErrors() async throws {
        // A refused action still comes back as JSON; it must fail, not read as output.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"error":{"code":2104},"success":false}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        await #expect(throws: DSMError.self) {
            _ = try await service.performProjectAction(.start, projectID: "missing")
        }
    }

    @Test func failedStreamKeepsItsExitCode() {
        let result = DockerStreamResult(output: "Error response from daemon\nExit Code: 1\n")
        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
        #expect(result.lines == ["Error response from daemon"])
    }

    @Test func imageListSendsMandatoryPagingAndDecodes() async throws {
        // DSM 7.4 answers error 114 when `limit`/`offset` are missing.
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"images":[{"created":1699728697,"description":"","digest":"","id":"sha256:abc","remote_digest":"","repository":"nginx","size":14682465,"tags":["latest"],"upgradable":false,"virtual_size":14682465}],"total":1}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let images = try await service.images()

        let image = try #require(images.first)
        #expect(image.displayName == "nginx:latest")
        #expect(image.sizeBytes == 14_682_465)
        #expect(!image.isUpgradable)
        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["limit"] == "-1")
        #expect(parameters["offset"] == "0")
        #expect(parameters["show_dsm"] == "false")
    }

    @Test func imageDeleteSendsRepositoryAndTagsAsJSONArray() async throws {
        // Captured contract: the target travels as one JSON array parameter.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.deleteImage(repository: "hello-world", tags: ["latest"])

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "delete")
        // JSONEncoder does not guarantee key order: compare the decoded structure.
        struct Target: Decodable, Equatable {
            let repository: String
            let tags: [String]
        }
        let payload = try #require(parameters["images"]?.data(using: .utf8))
        let targets = try JSONDecoder().decode([Target].self, from: payload)
        #expect(targets == [Target(repository: "hello-world", tags: ["latest"])])
    }

    @Test func decodesNetworksAndFlagsBuiltInOnes() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"network":[{"containers":["web"],"driver":"bridge","enable_ipv6":false,"gateway":"172.29.0.1","id":"e163","iprange":"","name":"bridge","subnet":"172.29.0.0/16"}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let networks = try await service.networks()

        let network = try #require(networks.first)
        #expect(network.isBuiltIn)
        #expect(network.subnet == "172.29.0.0/16")
        #expect(network.ipRange == nil)
        #expect(network.containerNames == ["web"])
    }

    private func makeService(stub: DSMRequestStub) -> DSMContainerService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Docker.Container": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            ),
            "SYNO.Docker.Container.Resource": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1
            ),
            "SYNO.Docker.Container.Log": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Docker.Project": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Docker.Image": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Docker.Network": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Docker.Registry": APIInfoEntry(
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
        return DSMContainerService(transport: transport)
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
