//
//  DockerImage.swift
//  dsmaccess
//
//  Local images and registries of Container Manager.
//

import Foundation

struct DockerImage: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let repository: String
    let tags: [String]
    let sizeBytes: Int64?
    let virtualSizeBytes: Int64?
    let createdAt: Date?
    let isUpgradable: Bool
    let descriptionText: String?

    /// What Container Manager shows in its Image tab: `repository:tag`, or the repository alone
    /// when the image carries no tag.
    var displayName: String {
        guard let tag = tags.first, !tag.isEmpty else { return repository }
        return "\(repository):\(tag)"
    }

    /// The archive `export` writes. DSM names the file itself and takes no say in it, so the
    /// app works the name out the same way to be able to tell the user where it landed:
    /// `containrrr/watchtower:latest` becomes `containrrr-watchtower(latest).syno.tar`.
    func exportArchiveName(tag: String) -> String {
        "\(repository.replacingOccurrences(of: "/", with: "-"))(\(tag)).syno.tar"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case repository
        case tags
        case sizeBytes = "size"
        case virtualSizeBytes = "virtual_size"
        case createdAt = "created"
        case isUpgradable = "upgradable"
        case descriptionText = "description"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        repository = try values.requiredFlexString(.repository)
        id = values.flexString(.id) ?? repository
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        sizeBytes = values.flexInt64(.sizeBytes)
        virtualSizeBytes = values.flexInt64(.virtualSizeBytes)
        createdAt = values.flexInt64(.createdAt).map {
            Date(timeIntervalSince1970: TimeInterval($0))
        }
        isUpgradable = values.flexBool(.isUpgradable) ?? false
        descriptionText = values.flexString(.descriptionText).flatMap {
            $0.isEmpty ? nil : $0
        }
    }
}

struct DockerImageList: nonisolated Decodable, Sendable {
    let images: [DockerImage]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case images
        case total
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        images = try values.decodeIfPresent([DockerImage].self, forKey: .images) ?? []
        total = values.flexInt(.total)
    }
}

struct DockerRegistry: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let url: String
    let isSynology: Bool
    let usesRegistryMirror: Bool
    let mirrorURLs: [String]
    let trustsSelfSignedCertificate: Bool
    /// Account the registry signs in with, empty when it needs none. Captured on DSM 7.4: the
    /// password is never returned, so an edit form cannot prefill it.
    let username: String

    var id: String { name }

    /// Docker Hub cannot be removed, and DSM decides that on the **name** rather than on the
    /// `syno` flag — verified in Container Manager's own client.
    var isDefaultRegistry: Bool {
        name.caseInsensitiveCompare("Docker Hub") == .orderedSame
    }

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case isSynology = "syno"
        case usesRegistryMirror = "enable_registry_mirror"
        case mirrorURLs = "mirror_urls"
        case trustsSelfSignedCertificate = "enable_trust_SSC"
        case username
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        url = values.flexString(.url) ?? ""
        isSynology = values.flexBool(.isSynology) ?? false
        usesRegistryMirror = values.flexBool(.usesRegistryMirror) ?? false
        mirrorURLs = try values.decodeIfPresent([String].self, forKey: .mirrorURLs) ?? []
        trustsSelfSignedCertificate = values.flexBool(.trustsSelfSignedCertificate) ?? false
        username = values.flexString(.username) ?? ""
    }
}

/// One image found by `SYNO.Docker.Registry search`, which queries the active registry only.
struct DockerRegistrySearchResult: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let descriptionText: String
    let downloads: Int64?
    let starCount: Int?
    let isOfficial: Bool
    let isAutomated: Bool
    /// URL of the registry that answered, which is the active one.
    let registry: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case descriptionText = "description"
        case downloads
        case starCount = "star_count"
        case isOfficial = "is_official"
        case isAutomated = "is_automated"
        case registry
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        descriptionText = values.flexString(.descriptionText) ?? ""
        downloads = values.flexInt64(.downloads)
        starCount = values.flexInt(.starCount)
        isOfficial = values.flexBool(.isOfficial) ?? false
        isAutomated = values.flexBool(.isAutomated) ?? false
        registry = values.flexString(.registry) ?? ""
    }
}

/// A page of search results. Captured on DSM 7.4: the results sit under a **second** `data`
/// key inside the response payload, not under `images` as Container Manager's own JavaScript
/// suggests — its `title`/`stars`/`link` are display names, not wire fields.
struct DockerRegistrySearchPage: nonisolated Decodable, Sendable {
    let results: [DockerRegistrySearchResult]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case results = "data"
        case total
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        results = try values.decodeIfPresent([DockerRegistrySearchResult].self, forKey: .results) ?? []
        total = values.flexInt(.total)
    }
}

/// What an image declares about itself, as DSM's own “Details” screen shows it. Captured on
/// DSM 7.4 from `SYNO.Docker.Image get`, which needs the image identifier alone.
///
/// The reply also carries `image` and `tag`, and **both are always empty** — verified across
/// every image on the NAS — so the name has to come from the listing instead.
struct DockerImageDetail: nonisolated Decodable, Sendable {
    let id: String
    let author: String
    let dockerVersion: String
    let digest: String?
    let command: [String]
    let entrypoint: [String]
    let environment: [DockerImageEnvironmentVariable]
    let exposedPorts: [DockerImagePort]
    let volumes: [String]
    let sizeBytes: Int64?
    let virtualSizeBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case dockerVersion = "docker_version"
        case digest
        case command = "cmd"
        case entrypoint
        case environment = "env"
        case exposedPorts = "ports"
        case volumes
        case sizeBytes = "size"
        case virtualSizeBytes = "virtual_size"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.flexString(.id) ?? ""
        author = values.flexString(.author) ?? ""
        dockerVersion = values.flexString(.dockerVersion) ?? ""
        digest = values.flexString(.digest).flatMap { $0.isEmpty ? nil : $0 }
        command = try values.decodeIfPresent([String].self, forKey: .command) ?? []
        entrypoint = try values.decodeIfPresent([String].self, forKey: .entrypoint) ?? []
        environment = try values.decodeIfPresent(
            [DockerImageEnvironmentVariable].self,
            forKey: .environment
        ) ?? []
        exposedPorts = try values.decodeIfPresent([DockerImagePort].self, forKey: .exposedPorts) ?? []
        volumes = try values.decodeIfPresent([String].self, forKey: .volumes) ?? []
        sizeBytes = values.flexInt64(.sizeBytes)
        virtualSizeBytes = values.flexInt64(.virtualSizeBytes)
    }
}

struct DockerImageEnvironmentVariable: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let key: String
    let value: String

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key
        case value
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        key = try values.requiredFlexString(.key)
        value = values.flexString(.value) ?? ""
    }
}

/// A port the image declares. Captured on DSM 7.4: the port arrives as a **string**.
struct DockerImagePort: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let port: String
    let networkProtocol: String

    var id: String { "\(port)/\(networkProtocol)" }

    /// What Docker itself writes, and what a Dockerfile shows: `8080/tcp`.
    var displayName: String {
        networkProtocol.isEmpty ? port : "\(port)/\(networkProtocol)"
    }

    enum CodingKeys: String, CodingKey {
        case port
        case networkProtocol = "protocol"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        port = try values.requiredFlexString(.port)
        networkProtocol = values.flexString(.networkProtocol) ?? ""
    }
}

/// One available version of an image, as `SYNO.Docker.Registry tags` returns it.
struct DockerImageTag: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let tag: String

    var id: String { tag }

    enum CodingKeys: String, CodingKey {
        case tag
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tag = try values.requiredFlexString(.tag)
    }
}

struct DockerRegistryList: nonisolated Decodable, Sendable {
    let registries: [DockerRegistry]
    /// Name of the registry images are currently pulled from.
    let selected: String?

    enum CodingKeys: String, CodingKey {
        case registries
        case selected = "using"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        registries = try values.decodeIfPresent([DockerRegistry].self, forKey: .registries) ?? []
        selected = values.flexString(.selected)
    }
}

/// `pull_start` answers with the identifier to poll `pull_status` with.
struct DockerImagePullTask: nonisolated Decodable, Equatable, Sendable {
    let taskID: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        taskID = try values.requiredFlexString(.taskID)
    }
}

/// Progress of a `pull_start` download, polled through `pull_status`. Captured on DSM 7.4:
/// `{"description":…,"downloaded":0,"finished":true,"repository":"docker.io/hello-world","tag":"latest"}`.
struct DockerImagePullStatus: nonisolated Decodable, Equatable, Sendable {
    let isFinished: Bool
    let downloadedBytes: Int64?
    let repository: String?
    let tag: String?

    enum CodingKeys: String, CodingKey {
        case isFinished = "finished"
        case downloadedBytes = "downloaded"
        case repository
        case tag
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isFinished = values.flexBool(.isFinished) ?? false
        downloadedBytes = values.flexInt64(.downloadedBytes)
        repository = values.flexString(.repository)
        tag = values.flexString(.tag)
    }
}
