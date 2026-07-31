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

struct DockerNetworkList: nonisolated Decodable, Sendable {
    let networks: [DockerNetwork]

    enum CodingKeys: String, CodingKey { case network }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        networks = try values.decodeIfPresent([DockerNetwork].self, forKey: .network) ?? []
    }
}
