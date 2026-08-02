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
        #expect(try query(from: requests[0])["type"] == #""all""#)
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

    @Test func streamWithoutExitCodeReadsAsFailure() {
        // Observed on DSM 7.4: a build that dies at the image pull ends with the daemon error,
        // without any Exit Code line.
        let result = DockerStreamResult(
            output: "teamtalk_canour Pulling\nteamtalk_canour Error\npull access denied\n"
        )
        #expect(!result.succeeded)
        #expect(result.exitCode == nil)
        #expect(result.lines.count == 3)
    }

    @Test func projectStatusParsesObservedValues() {
        #expect(DockerProjectStatus(rawValue: "RUNNING") == .running)
        #expect(DockerProjectStatus(rawValue: "STOPPED") == .stopped)
        // Left behind by a failed compose build; stays until a build succeeds.
        #expect(DockerProjectStatus(rawValue: "BUILD_FAILED") == .buildFailed)
        #expect(DockerProjectStatus(rawValue: "SOMETHING_NEW") == .unknown("SOMETHING_NEW"))
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

    @Test func containerForceStopSendsSignalAsAnInteger() async throws {
        // Captured contract: `signal` is the integer 9. "9", "SIGKILL" and "KILL" are all
        // refused by DSM with error 114, and nothing in the build would catch the quoting.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.killContainer(name: "web")

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "signal")
        #expect(parameters["name"] == #""web""#)
        #expect(parameters["signal"] == "9")
    }

    @Test func containerResetPreservesTheProfile() async throws {
        // Captured contract: Reset is the same `delete` method, told to keep the profile.
        // Sending false here would delete the container instead of recreating it.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.resetContainer(name: "web")

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "delete")
        #expect(parameters["name"] == #""web""#)
        #expect(parameters["force"] == "false")
        #expect(parameters["preserve_profile"] == "true")
    }

    @Test func containerDeleteSendsCapturedParameters() async throws {
        // Captured contract: DSM's Delete action, distinct from its Reset which preserves
        // the profile.
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.deleteContainer(name: "web")

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "delete")
        #expect(parameters["name"] == #""web""#)
        #expect(parameters["force"] == "false")
        #expect(parameters["preserve_profile"] == "false")
    }

    @Test func decodesProcessesWithStringPIDs() async throws {
        // Captured on DSM 7.4: `pid` is a string, `cpu` a fraction of a percent.
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"processes":[{"command":"openvpn --config fr.ovpn","cpu":0.17,"memory":5808128,"memoryPercent":0.14,"pid":"17787","start":"Jul30"}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let processes = try await service.containerProcesses(name: "transmission")

        let process = try #require(processes.first)
        #expect(process.pid == "17787")
        #expect(process.cpuPercent == 0.17)
        #expect(process.memoryBytes == 5_808_128)
    }

    @Test func dockerLogRequestCarriesCapturedFiltersAndDecodesCounts() async throws {
        // Captured contract: `action=load` is mandatory alongside offset/limit.
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"error_count":0,"info_count":615,"limit":3,"logs":[{"event":"Delete image hello-world:latest","level":"info","log_type":"dockerlog","time":"2026/07/31 20:13:45","user":"math65"}],"offset":0,"total":615,"warn_count":0}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let page = try await service.dockerLog(offset: 0, limit: 3, level: .information, keyword: "image")

        #expect(page.total == 615)
        let entry = try #require(page.entries.first)
        #expect(entry.event == "Delete image hello-world:latest")
        #expect(entry.user == "math65")
        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["action"] == #""load""#)
        // Measured vocabulary: the filter wants full words, the entries carry `info`/`err`.
        #expect(parameters["loglevel"] == #""information""#)
        #expect(parameters["filter_content"] == #""image""#)
        #expect(parameters["sort_by"] == #""time""#)
        #expect(parameters["datefrom"] == "0")
        #expect(parameters["dateto"] == "0")
    }

    @Test func imageUpgradeStartSendsRepositoryOnly() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"task_id":"@administrators/UPGRADE1"}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let task = try await service.startImageUpgrade(repository: "nginx")

        #expect(task.taskID == "@administrators/UPGRADE1")
        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "upgrade_start")
        #expect(parameters["repository"] == #""nginx""#)
        #expect(parameters["tag"] == nil)
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

    // MARK: - Project creation

    @Test func sendsTheWholeCreationProfileMeasuredOnDSM74() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"id":"project-id","name":"web","services":["hello"]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let creation = try await service.createProject(
            name: "web",
            sharePath: "/docker/web",
            content: "services: {hello: {image: hello-world}}"
        )

        #expect(creation.id == "project-id")
        #expect(creation.name == "web")
        #expect(creation.services == ["hello"])

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["api"] == "SYNO.Docker.Project")
        #expect(parameters["method"] == "create")
        #expect(parameters["name"] == #""web""#)
        // JSONEncoder escapes the slashes of a path. Checked against the NAS: DSM answers a
        // path sent as "\/docker\/x" exactly as it answers "/docker/x".
        #expect(parameters["share_path"] == #""\/docker\/web""#)
        #expect(parameters["content"] == #""services: {hello: {image: hello-world}}""#)
        // DSM sends the four portal fields even with the portal off; leaving them out is what
        // its own client never does, so the app does not either.
        #expect(parameters["enable_service_portal"] == "false")
        #expect(parameters["service_portal_name"] == #""""#)
        #expect(parameters["service_portal_port"] == "0")
        #expect(parameters["service_portal_protocol"] == #""""#)
    }

    @Test func readsWhatACandidateFolderAlreadyHolds() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"compose_path":"/volume1/docker/web/compose.yaml","content":"services: {}","is_docker_compose_yml_exist":true}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let info = try await service.projectShareInfo(path: "/docker/web")

        #expect(info.hasComposeFile)
        #expect(info.content == "services: {}")
        // The answer mixes both path shapes: share-relative in, absolute out.
        #expect(info.composePath == "/volume1/docker/web/compose.yaml")

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "get_share_info")
        #expect(parameters["path"] == #""\/docker\/web""#)
    }

    @Test func readsAnEmptyFolderWithoutTreatingItAsAFailure() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"compose_path":"","content":"","is_docker_compose_yml_exist":false}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let info = try await service.projectShareInfo(path: "/docker")

        #expect(!info.hasComposeFile)
        #expect(info.content.isEmpty)
        #expect(info.composePath.isEmpty)
    }

    @Test func updatesOnlyTheComposeFileOfAProject() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.updateProject(id: "project-id", content: "services: {}")

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "update")
        #expect(parameters["id"] == #""project-id""#)
        #expect(parameters["content"] == #""services: {}""#)
        #expect(parameters["name"] == nil)
        #expect(parameters["share_path"] == nil)
    }

    @Test func acceptsTheProjectNamesDSMAcceptsAndRefusesTheOthers() {
        #expect(DockerProject.isValidName("web"))
        #expect(DockerProject.isValidName("dsmaccess-test"))
        #expect(DockerProject.isValidName("app_2"))
        #expect(DockerProject.isValidName("2048"))

        #expect(!DockerProject.isValidName(""))
        // Measured on the NAS: each of these answers error 2206.
        #expect(!DockerProject.isValidName("Web"))
        #expect(!DockerProject.isValidName("DSM Access Test"))
        #expect(!DockerProject.isValidName("-web"))
        #expect(!DockerProject.isValidName("_web"))
        #expect(!DockerProject.isValidName("web.app"))
        #expect(!DockerProject.isValidName("projet-éclair"))
    }

    // MARK: - Networks

    @Test func omitsTheAddressFieldsWhenAddressingIsAutomatic() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.createNetwork(
            name: "app-net",
            addressing: .automatic,
            disablesMasquerade: false,
            enablesIPv6: false
        )

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "create")
        #expect(parameters["name"] == #""app-net""#)
        #expect(parameters["disable_masquerade"] == "false")
        #expect(parameters["enable_ipv6"] == "false")
        // DSM drops these three in automatic mode rather than sending them empty, and an
        // empty subnet is not the same request as no subnet at all.
        #expect(parameters["subnet"] == nil)
        #expect(parameters["iprange"] == nil)
        #expect(parameters["gateway"] == nil)
        // DSM only ever creates bridges, and sends no driver.
        #expect(parameters["driver"] == nil)
    }

    @Test func sendsTheThreeAddressFieldsWhenAddressingIsManual() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.createNetwork(
            name: "app-net",
            addressing: .manual(
                subnet: "172.31.0.0/16",
                ipRange: "172.31.0.0/24",
                gateway: "172.31.0.1"
            ),
            disablesMasquerade: true,
            enablesIPv6: true
        )

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["subnet"] == #""172.31.0.0\/16""#)
        #expect(parameters["iprange"] == #""172.31.0.0\/24""#)
        #expect(parameters["gateway"] == #""172.31.0.1""#)
        #expect(parameters["disable_masquerade"] == "true")
        #expect(parameters["enable_ipv6"] == "true")
    }

    @Test func removesNetworksByNameAlone() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"failed":[]}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let result = try await service.removeNetworks(named: ["app-net"])

        #expect(result.failed.isEmpty)
        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "remove")
        // DSM's own client posts whole network objects; the name alone is enough, checked
        // against the NAS.
        #expect(parameters["networks"] == #"[{"name":"app-net"}]"#)
    }

    @Test func reportsARefusedRemovalThatDSMStillCallsASuccess() async throws {
        // Measured on DSM 7.4: removing a network that does not exist answers success: true
        // and hides the refusal in data.failed. Trusting the envelope would announce a
        // deletion that never happened.
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"failed":[{"errMsg":"{\"message\":\"network app-net not found\"}","network":"app-net","statusCode":404}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let result = try await service.removeNetworks(named: ["app-net"])

        let failure = try #require(result.failed.first)
        #expect(failure.network == "app-net")
        #expect(failure.statusCode == 404)
        // The daemon's message arrives wrapped in JSON inside a string.
        #expect(failure.message == "network app-net not found")
    }

    @Test func keepsAnUnparsableRemovalMessageRatherThanDroppingIt() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"failed":[{"errMsg":"plain refusal","network":"app-net"}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let result = try await service.removeNetworks(named: ["app-net"])

        let failure = try #require(result.failed.first)
        #expect(failure.message == "plain refusal")
        #expect(failure.statusCode == nil)
    }

    @Test func sendsTheWantedContainerSetWithTheCamelCaseNetworkName() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.setNetworkContainers(
            networkName: "app-net",
            containerNames: ["web", "db"]
        )

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "set")
        // camelCase here, alone in this module.
        #expect(parameters["networkName"] == #""app-net""#)
        #expect(parameters["containers"] == #"["web","db"]"#)
    }

    @Test func listsAttachableContainersWithMandatoryPaging() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"containers":[{"name":"web"}]}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let containers = try await service.networkContainers()

        #expect(containers.map(\.name) == ["web"])
        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["method"] == "list_container")
        #expect(parameters["limit"] == "-1")
        #expect(parameters["offset"] == "0")
    }

    /// Captured contract: `path` is the **folder**, not the file — a file path answers 117 —
    /// and all three parameters are required.
    @Test func exportsAnImageIntoAFolderAndNotOntoAFilePath() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"task_id":"@administrators/SYNO_DOCKER"}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.exportImage(repository: "alpine", tag: "latest", folderPath: "/docker")

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Docker.Image")
        #expect(parameters["method"] == "export")
        #expect(parameters["repo"] == #""alpine""#)
        #expect(parameters["tag"] == #""latest""#)
        #expect(parameters["path"] == #""\/docker""#)
    }

    @Test func importsAnArchiveThroughItsPathRelativeToTheShare() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.importImage(path: "/docker/alpine(latest).syno.tar")

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "import")
        #expect(parameters["path"] == #""\/docker\/alpine(latest).syno.tar""#)
    }

    /// DSM names the exported archive itself, so the app works the name out the same way to
    /// be able to say where the file landed.
    @Test func buildsTheArchiveNameDSMWillChoose() throws {
        let payload = Data(
            #"{"images":[{"repository":"containrrr/watchtower","tags":["latest"],"id":"sha256:a"}]}"#.utf8
        )
        let list = try JSONDecoder().decode(DockerImageList.self, from: payload)
        let image = try #require(list.images.first)

        #expect(image.exportArchiveName(tag: "latest") == "containrrr-watchtower(latest).syno.tar")
    }

    /// Captured contract: `identity` alone, and the reply carries `image` and `tag` that are
    /// always empty — the name has to come from the listing. `digest` arrives null, and the
    /// exposed ports arrive as strings.
    @Test func decodesImageDetailWithStringPortsAndNullDigest() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"author":"","cmd":[],"digest":null,"docker_version":"","entrypoint":["/watchtower"],"env":[{"key":"PATH","value":"/usr/local/sbin:/usr/bin"}],"id":"sha256:e7dd50d07b86","image":"","ports":[{"port":"8080","protocol":"tcp"}],"size":14682465,"tag":"","virtual_size":14682465,"volumes":["/config"]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let detail = try await service.imageDetail(identity: "sha256:e7dd50d07b86")

        #expect(detail.digest == nil)
        #expect(detail.entrypoint == ["/watchtower"])
        #expect(detail.command.isEmpty)
        #expect(detail.volumes == ["/config"])
        #expect(detail.sizeBytes == 14_682_465)
        let port = try #require(detail.exposedPorts.first)
        #expect(port.port == "8080")
        #expect(port.displayName == "8080/tcp")
        let variable = try #require(detail.environment.first)
        #expect(variable.key == "PATH")

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Docker.Image")
        #expect(parameters["method"] == "get")
        #expect(parameters["identity"] == #""sha256:e7dd50d07b86""#)
    }

    // MARK: - Registries

    @Test func decodesRegistryListWithTheActiveRegistryAndItsAccount() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"offset":0,"total":2,"using":"Docker Hub","registries":[{"enable_registry_mirror":false,"enable_trust_SSC":false,"mirror_urls":[],"name":"Docker Hub","syno":true,"url":"https://registry.hub.docker.com"},{"enable_trust_SSC":true,"name":"work","syno":false,"url":"https://ghcr.io","username":"builder"}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let list = try await service.registries()

        #expect(list.selected == "Docker Hub")
        #expect(list.registries.map(\.name) == ["Docker Hub", "work"])
        let hub = try #require(list.registries.first)
        #expect(hub.username.isEmpty)
        let private_ = try #require(list.registries.last)
        #expect(private_.username == "builder")
        #expect(private_.trustsSelfSignedCertificate)
        // A registry the NAS returns without mirror keys at all must still decode.
        #expect(private_.mirrorURLs.isEmpty)
    }

    /// DSM refuses to delete Docker Hub, and decides that on the name rather than on `syno`.
    @Test func recognisesTheDefaultRegistryByNameNotBySynologyFlag() throws {
        let payload = Data(
            #"{"registries":[{"name":"Docker Hub","syno":false,"url":"https://registry.hub.docker.com"},{"name":"work","syno":true,"url":"https://ghcr.io"}]}"#.utf8
        )
        let list = try JSONDecoder().decode(DockerRegistryList.self, from: payload)

        let hub = try #require(list.registries.first)
        let other = try #require(list.registries.last)
        #expect(hub.isDefaultRegistry)
        #expect(!other.isDefaultRegistry)
    }

    /// Captured contract: `name` and `url` are both required, and the password is only sent
    /// when filled — an empty one would overwrite the stored password with nothing.
    @Test func createsRegistryWithoutSendingAnEmptyPassword() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.createRegistry(
            name: "work",
            url: "https://ghcr.io",
            username: "",
            password: "",
            trustsSelfSignedCertificate: true
        )

        let request = try #require(await stub.requests.first)
        let parameters = try query(from: request)
        #expect(parameters["api"] == "SYNO.Docker.Registry")
        #expect(parameters["method"] == "create")
        #expect(parameters["name"] == #""work""#)
        // JSON escapes the slashes, as it does for the project share paths.
        #expect(parameters["url"] == #""https:\/\/ghcr.io""#)
        #expect(parameters["enable_trust_SSC"] == "true")
        #expect(parameters["password"] == nil)
        #expect(parameters["username"] == nil)
    }

    @Test func createsRegistryWithCredentialsWhenTheyAreFilled() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.createRegistry(
            name: "work",
            url: "https://ghcr.io",
            username: "builder",
            password: "secret",
            trustsSelfSignedCertificate: false
        )

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["username"] == #""builder""#)
        #expect(parameters["password"] == #""secret""#)
    }

    /// Captured contract: `set` designates its target by `oldname` — DSM answers 101 without
    /// it — which is also what makes renaming possible.
    @Test func updatesRegistryThroughOldNameSoRenamingWorks() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.updateRegistry(
            oldName: "work",
            name: "work-eu",
            url: "https://ghcr.io",
            username: "builder",
            password: "",
            trustsSelfSignedCertificate: false
        )

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "set")
        #expect(parameters["oldname"] == #""work""#)
        #expect(parameters["name"] == #""work-eu""#)
        #expect(parameters["password"] == nil)
    }

    @Test func sendsTheRegistryNameToDeleteAndToUse() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.deleteRegistry(named: "work")
        try await service.useRegistry(named: "Docker Hub")

        let requests = await stub.requests
        #expect(try query(from: requests[0])["method"] == "delete")
        #expect(try query(from: requests[0])["name"] == #""work""#)
        #expect(try query(from: requests[1])["method"] == "using")
        #expect(try query(from: requests[1])["name"] == #""Docker Hub""#)
    }

    /// Captured contract: the results sit under a second `data` key. Container Manager's own
    /// JavaScript names them `title`/`stars`/`link`, which are display names and decode to
    /// nothing.
    @Test func decodesSearchResultsFromTheNestedDataKey() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(
                #"{"success":true,"data":{"limit":50,"offset":0,"page_size":50,"total":103773,"data":[{"description":"A minimal Docker image","downloads":12057019456,"is_automated":false,"is_official":true,"name":"alpine","registry":"https://registry.hub.docker.com","star_count":11552}]}}"#.utf8
            )),
        ])
        let service = makeService(stub: stub)

        let page = try await service.searchImages(keyword: "alpine", offset: 0, limit: 50)

        #expect(page.total == 103_773)
        let result = try #require(page.results.first)
        #expect(result.name == "alpine")
        #expect(result.downloads == 12_057_019_456)
        #expect(result.starCount == 11_552)
        #expect(result.isOfficial)
        #expect(!result.isAutomated)

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "search")
        #expect(parameters["q"] == #""alpine""#)
        #expect(parameters["page_size"] == "50")
    }

    /// Captured contract: the parameter is `repo`. `repository` answers 1052, as if the image
    /// did not exist.
    @Test func readsImageTagsThroughRepoAndNotRepository() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":[{"tag":"latest"},{"tag":"3.19"}]}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        let tags = try await service.imageTags(repository: "alpine")

        #expect(tags.map(\.tag) == ["latest", "3.19"])
        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "tags")
        #expect(parameters["repo"] == #""alpine""#)
        #expect(parameters["repository"] == nil)
    }

    private func makeService(stub: DSMRequestStub) -> DSMContainerService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            // The real DS920+ declares requestFormat JSON for every SYNO.Docker API.
            "SYNO.Docker.Container": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
            ),
            "SYNO.Docker.Container.Resource": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 1,
                requestFormat: "JSON"
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
            "SYNO.Docker.Log": APIInfoEntry(
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
