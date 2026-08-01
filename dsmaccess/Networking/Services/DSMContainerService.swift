//
//  DSMContainerService.swift
//  dsmaccess
//
//  Inventaire, cycle de vie et journaux de Container Manager.
//

import Foundation

@MainActor
final class DSMContainerService {
    private static let containerAPI = DSMAPI("SYNO.Docker.Container", preferredVersion: 1)
    private static let resourceAPI = DSMAPI("SYNO.Docker.Container.Resource", preferredVersion: 1)
    private static let logAPI = DSMAPI("SYNO.Docker.Container.Log", preferredVersion: 1)
    private static let projectAPI = DSMAPI("SYNO.Docker.Project", preferredVersion: 1)
    private static let imageAPI = DSMAPI("SYNO.Docker.Image", preferredVersion: 1)
    private static let networkAPI = DSMAPI("SYNO.Docker.Network", preferredVersion: 1)
    private static let registryAPI = DSMAPI("SYNO.Docker.Registry", preferredVersion: 1)
    private static let dockerLogAPI = DSMAPI("SYNO.Docker.Log", preferredVersion: 1)

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func containers() async throws -> [ContainerItem] {
        let result = try await transport.read(
            api: Self.containerAPI,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(-1),
                "type": .string("all"),
            ],
            as: ContainerList.self
        )
        guard transport.capabilities.supports(Self.resourceAPI.name) else {
            return result.containers
        }

        let resourceResult = try await transport.read(
            api: Self.resourceAPI,
            method: "get",
            as: ContainerResourceList.self
        )
        var resourcesByName = [String: ContainerResource]()
        for resource in resourceResult.resources {
            resourcesByName[resource.name] = resource
        }
        return result.containers.map { container in
            guard let resource = resourcesByName[container.name] else { return container }
            return container.applying(resource)
        }
    }

    func perform(_ action: ContainerAction, name: String) async throws {
        try await transport.perform(
            api: Self.containerAPI,
            method: action.rawValue,
            parameters: ["name": .string(name)]
        )
    }

    func logs(name: String, limit: Int = 300) async throws -> [ContainerLogEntry] {
        guard transport.capabilities.supports(Self.logAPI.name) else { return [] }
        let result = try await transport.read(
            api: Self.logAPI,
            method: "get",
            parameters: [
                "name": .string(name),
                "from": .string(""),
                "to": .string(""),
                "level": .string(""),
                "keyword": .string(""),
                "sort_by": .string("time"),
                "sort_dir": .string("DESC"),
                "offset": .integer(0),
                "limit": .integer(limit),
            ],
            as: ContainerLogList.self
        )
        return result.logs
    }

    /// Deletes a container. Captured contract: `preserve_profile` false matches DSM's own
    /// Delete action (true would be its Reset, which keeps the profile for recreation).
    func deleteContainer(name: String) async throws {
        try await transport.perform(
            api: Self.containerAPI,
            method: "delete",
            parameters: [
                "name": .string(name),
                "force": .boolean(false),
                "preserve_profile": .boolean(false),
            ]
        )
    }

    func containerProcesses(name: String) async throws -> [ContainerProcess] {
        let result = try await transport.read(
            api: Self.containerAPI,
            method: "get_process",
            parameters: ["name": .string(name)],
            as: ContainerProcessList.self
        )
        return result.processes
    }

    // MARK: - Projects

    func projects() async throws -> [DockerProject] {
        let result = try await transport.read(
            api: Self.projectAPI,
            method: "list",
            as: DockerProjectList.self
        )
        return result.projects
    }

    func project(id: String) async throws -> DockerProject {
        try await transport.read(
            api: Self.projectAPI,
            method: "get",
            parameters: ["id": .string(id)],
            as: DockerProject.self
        )
    }

    /// Runs a compose action. These `*_stream` methods answer with plain text — the
    /// docker-compose output followed by an `Exit Code:` line — instead of the usual JSON
    /// envelope, so they bypass the decoding path. Mutations: a single attempt, never replayed.
    func performProjectAction(
        _ action: DockerProjectAction,
        projectID: String
    ) async throws -> DockerStreamResult {
        let url = try await transport.makeURL(
            api: Self.projectAPI,
            method: action.rawValue,
            parameters: ["id": .string(projectID)]
        )
        var request = URLRequest(url: url)
        // Compose pulls and builds can legitimately take a while.
        request.timeoutInterval = 300
        let (data, response) = try await transport.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw DSMError.invalidResponse
        }
        // A failed call (bad identifier, privilege) still comes back as the JSON envelope.
        if let envelope = try? JSONDecoder().decode(DSMResponse<EmptyData>.self, from: data),
           envelope.success == false {
            throw transport.error(from: envelope.error)
        }
        return DockerStreamResult(output: text)
    }

    /// Asks what a candidate folder already holds, so creation can offer to reuse a compose
    /// file instead of overwriting it. The path is the share-relative one (`/docker/app`).
    func projectShareInfo(path: String) async throws -> DockerProjectShareInfo {
        try await transport.read(
            api: Self.projectAPI,
            method: "get_share_info",
            parameters: ["path": .string(path)],
            as: DockerProjectShareInfo.self
        )
    }

    /// Creates a compose project. Captured contract: DSM sends the whole profile, the four web
    /// portal fields included, and their neutral values are what it sends when the portal is
    /// off. The portal itself needs Web Station, which this app does not configure.
    func createProject(
        name: String,
        sharePath: String,
        content: String
    ) async throws -> DockerProjectCreation {
        try await transport.value(
            api: Self.projectAPI,
            method: "create",
            parameters: [
                "name": .string(name),
                "content": .string(content),
                "share_path": .string(sharePath),
                "enable_service_portal": .boolean(false),
                "service_portal_name": .string(""),
                "service_portal_port": .integer(0),
                "service_portal_protocol": .string(""),
            ],
            as: DockerProjectCreation.self
        )
    }

    /// Rewrites the compose file of an existing project. This only saves it: bringing the
    /// change into effect takes a `build` action afterwards, as DSM's own editor offers.
    func updateProject(id: String, content: String) async throws {
        try await transport.perform(
            api: Self.projectAPI,
            method: "update",
            parameters: [
                "id": .string(id),
                "content": .string(content),
            ]
        )
    }

    /// Deletes a project. Captured contract: the folder and its `compose.yaml` stay on disk.
    func deleteProject(id: String) async throws {
        try await transport.perform(
            api: Self.projectAPI,
            method: "delete",
            parameters: ["id": .string(id)]
        )
    }

    // MARK: - Images

    func images() async throws -> [DockerImage] {
        // `limit` and `offset` are mandatory: DSM 7.4 answers error 114 without them.
        let result = try await transport.read(
            api: Self.imageAPI,
            method: "list",
            parameters: [
                "limit": .integer(-1),
                "offset": .integer(0),
                "show_dsm": .boolean(false),
            ],
            as: DockerImageList.self
        )
        return result.images
    }

    /// Deletes one image. Captured contract: the target travels as a JSON array of
    /// repository/tags pairs, not as separate parameters.
    func deleteImage(repository: String, tags: [String]) async throws {
        struct Target: Encodable {
            let repository: String
            let tags: [String]
        }
        try await transport.perform(
            api: Self.imageAPI,
            method: "delete",
            parameters: ["images": try .json([Target(repository: repository, tags: tags)])]
        )
    }

    func startImagePull(repository: String, tag: String) async throws -> DockerImagePullTask {
        try await transport.value(
            api: Self.imageAPI,
            method: "pull_start",
            parameters: [
                "repository": .string(repository),
                "tag": .string(tag),
            ],
            as: DockerImagePullTask.self
        )
    }

    func imagePullStatus(taskID: String) async throws -> DockerImagePullStatus {
        try await transport.read(
            api: Self.imageAPI,
            method: "pull_status",
            parameters: ["task_id": .string(taskID)],
            as: DockerImagePullStatus.self
        )
    }

    /// Removes local images no container references, as Container Manager's own button does.
    func pruneImages() async throws {
        try await transport.perform(api: Self.imageAPI, method: "prune")
    }

    func startImageUpgrade(repository: String) async throws -> DockerImagePullTask {
        try await transport.value(
            api: Self.imageAPI,
            method: "upgrade_start",
            parameters: ["repository": .string(repository)],
            as: DockerImagePullTask.self
        )
    }

    func imageUpgradeStatus(taskID: String) async throws -> DockerImagePullStatus {
        try await transport.read(
            api: Self.imageAPI,
            method: "upgrade_status",
            parameters: ["task_id": .string(taskID)],
            as: DockerImagePullStatus.self
        )
    }

    // MARK: - Networks

    func networks() async throws -> [DockerNetwork] {
        let result = try await transport.read(
            api: Self.networkAPI,
            method: "list",
            as: DockerNetworkList.self
        )
        return result.networks
    }

    /// Creates a bridge network. Captured contract: there is no `driver` parameter — DSM only
    /// ever creates bridges — and in automatic addressing it **omits** subnet, range and
    /// gateway instead of sending them empty.
    func createNetwork(
        name: String,
        addressing: DockerNetworkAddressing,
        disablesMasquerade: Bool,
        enablesIPv6: Bool
    ) async throws {
        var parameters: [String: DSMParameter] = [
            "name": .string(name),
            "disable_masquerade": .boolean(disablesMasquerade),
            "enable_ipv6": .boolean(enablesIPv6),
        ]
        if case .manual(let subnet, let ipRange, let gateway) = addressing {
            parameters["subnet"] = .string(subnet)
            parameters["iprange"] = .string(ipRange)
            parameters["gateway"] = .string(gateway)
        }
        try await transport.perform(api: Self.networkAPI, method: "create", parameters: parameters)
    }

    /// Removes networks by name.
    ///
    /// Captured contract, and the reason this returns something: **DSM answers `success: true`
    /// even when it deleted nothing**, listing the refusals in `data.failed`. The caller has to
    /// read that list; the envelope alone would report a deletion that never happened. DSM's
    /// own client sends whole network objects here — only the name is needed, verified
    /// against the NAS.
    func removeNetworks(named names: [String]) async throws -> DockerNetworkRemovalResult {
        struct Target: Encodable {
            let name: String
        }
        return try await transport.value(
            api: Self.networkAPI,
            method: "remove",
            parameters: ["networks": try .json(names.map(Target.init))],
            as: DockerNetworkRemovalResult.self
        )
    }

    /// Sets which containers are attached to a network. Captured contract: `networkName` is
    /// camelCase here, alone in this module, and the list is the **wanted final set** — DSM
    /// works out for itself what to attach and what to detach.
    func setNetworkContainers(networkName: String, containerNames: [String]) async throws {
        try await transport.perform(
            api: Self.networkAPI,
            method: "set",
            parameters: [
                "networkName": .string(networkName),
                "containers": try .json(containerNames),
            ]
        )
    }

    /// The containers that can be attached to a network. It does not say which ones already
    /// are: that comes from the `containers` of each network in `list`.
    func networkContainers() async throws -> [DockerNetworkContainer] {
        let result = try await transport.read(
            api: Self.networkAPI,
            method: "list_container",
            parameters: [
                "limit": .integer(-1),
                "offset": .integer(0),
            ],
            as: DockerNetworkContainerList.self
        )
        return result.containers
    }

    // MARK: - Container Manager log

    func dockerLog(
        offset: Int,
        limit: Int,
        level: DockerLogLevelFilter,
        keyword: String
    ) async throws -> DockerLogPage {
        try await transport.read(
            api: Self.dockerLogAPI,
            method: "list",
            parameters: [
                "action": .string("load"),
                "offset": .integer(offset),
                "limit": .integer(limit),
                "sort_by": .string("time"),
                "sort_dir": .string("DESC"),
                "loglevel": .string(level.rawValue),
                "filter_content": .string(keyword),
                "datefrom": .integer(0),
                "dateto": .integer(0),
            ],
            as: DockerLogPage.self
        )
    }

    func clearDockerLog() async throws {
        try await transport.perform(api: Self.dockerLogAPI, method: "clear")
    }

    /// Exports the whole log to a file. On refusal DSM answers JSON instead of the file;
    /// the content type is what gives it away, as with the system log export.
    func exportDockerLog(format: DockerLogExportFormat, to destination: URL) async throws {
        let url = try await transport.makeURL(
            api: Self.dockerLogAPI,
            method: "export",
            parameters: [
                "format": .string(format.rawValue),
                "loglevel": .string(""),
                "filter_content": .string(""),
                "datefrom": .integer(0),
                "dateto": .integer(0),
            ]
        )
        let (temporaryURL, response) = try await transport.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        if let mimeType = response.mimeType, mimeType.contains("json") {
            let data = try await MultipartBodyFile.readData(at: temporaryURL)
            let decoded = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
            guard !decoded.success else { throw DSMError.invalidResponse }
            throw transport.error(from: decoded.error)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
    }

    // MARK: - Registries

    func registries() async throws -> DockerRegistryList {
        try await transport.read(
            api: Self.registryAPI,
            method: "get",
            as: DockerRegistryList.self
        )
    }
}
