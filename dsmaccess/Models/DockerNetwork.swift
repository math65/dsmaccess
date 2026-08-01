//
//  DockerNetwork.swift
//  dsmaccess
//
//  Container networks managed by Container Manager.
//

import Foundation

struct DockerNetwork: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let driver: String
    let subnet: String?
    let gateway: String?
    let ipRange: String?
    let enablesIPv6: Bool
    let containerNames: [String]

    var containerCount: Int { containerNames.count }

    /// The two networks Docker itself creates. They cannot be removed, and DSM greys the
    /// action out; the app must do the same.
    var isBuiltIn: Bool { name == "bridge" || name == "host" }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case driver
        case subnet
        case gateway
        case ipRange = "iprange"
        case enablesIPv6 = "enable_ipv6"
        case containerNames = "containers"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        id = values.flexString(.id) ?? name
        driver = values.flexString(.driver) ?? ""
        subnet = values.flexString(.subnet).flatMap { $0.isEmpty ? nil : $0 }
        gateway = values.flexString(.gateway).flatMap { $0.isEmpty ? nil : $0 }
        ipRange = values.flexString(.ipRange).flatMap { $0.isEmpty ? nil : $0 }
        enablesIPv6 = values.flexBool(.enablesIPv6) ?? false
        containerNames = try values.decodeIfPresent([String].self, forKey: .containerNames) ?? []
    }
}

/// IPv4 addressing of a network being created. DSM offers the same two modes, and **omits**
/// the three address fields in automatic mode rather than sending them empty.
enum DockerNetworkAddressing: Sendable, Equatable {
    case automatic
    /// All three are required by DSM in manual mode, and all three want CIDR notation for the
    /// subnet and the range, a bare address for the gateway.
    case manual(subnet: String, ipRange: String, gateway: String)
}

/// One network `remove` could not delete.
///
/// ⚠️ Measured on DSM 7.4: a removal that fails still answers `success: true`, and only says
/// so in this list. Reading it is what keeps the app from announcing a deletion that never
/// happened.
struct DockerNetworkRemovalFailure: nonisolated Decodable, Sendable {
    let network: String
    let statusCode: Int?
    /// DSM wraps the daemon's own message in here as a JSON string, e.g.
    /// `{"message":"network x not found"}`.
    let message: String?

    enum CodingKeys: String, CodingKey {
        case network
        case statusCode
        case message = "errMsg"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        network = values.flexString(.network) ?? ""
        statusCode = values.flexInt(.statusCode)
        message = Self.readableMessage(values.flexString(.message))
    }

    /// Unwraps the daemon message when it parses, and keeps the raw text when it does not.
    private static nonisolated func readableMessage(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["message"] as? String else {
            return raw
        }
        return message
    }
}

struct DockerNetworkRemovalResult: nonisolated Decodable, Sendable {
    let failed: [DockerNetworkRemovalFailure]

    enum CodingKeys: String, CodingKey { case failed }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        failed = try values.decodeIfPresent([DockerNetworkRemovalFailure].self, forKey: .failed) ?? []
    }
}

/// A container as `list_container` offers it for attaching to a network.
struct DockerNetworkContainer: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let name: String

    var id: String { name }

    enum CodingKeys: String, CodingKey { case name }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
    }
}

struct DockerNetworkContainerList: nonisolated Decodable, Sendable {
    let containers: [DockerNetworkContainer]

    enum CodingKeys: String, CodingKey { case containers }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        containers = try values.decodeIfPresent([DockerNetworkContainer].self, forKey: .containers) ?? []
    }
}

struct DockerNetworkList: nonisolated Decodable, Sendable {
    let networks: [DockerNetwork]

    enum CodingKeys: String, CodingKey { case network }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        networks = try values.decodeIfPresent([DockerNetwork].self, forKey: .network) ?? []
    }
}
