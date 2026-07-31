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

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case url
        case isSynology = "syno"
        case usesRegistryMirror = "enable_registry_mirror"
        case mirrorURLs = "mirror_urls"
        case trustsSelfSignedCertificate = "enable_trust_SSC"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        url = values.flexString(.url) ?? ""
        isSynology = values.flexBool(.isSynology) ?? false
        usesRegistryMirror = values.flexBool(.usesRegistryMirror) ?? false
        mirrorURLs = try values.decodeIfPresent([String].self, forKey: .mirrorURLs) ?? []
        trustsSelfSignedCertificate = values.flexBool(.trustsSelfSignedCertificate) ?? false
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
