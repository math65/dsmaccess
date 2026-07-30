//
//  NetworkInfo.swift
//  dsmaccess
//
//  The NAS's identity and network configuration.
//

import Foundation

struct NetworkInfo: nonisolated Decodable, Sendable {
    let serverName: String?
    let gateway: String?
    let dnsPrimary: String?
    let dnsSecondary: String?
    let dnsManual: Bool?
    let v6gateway: String?
    let enableWinDomain: Bool?
    let gatewayInfo: Interface?

    struct Interface: nonisolated Decodable, Sendable {
        let ifname: String?
        let ip: String?
        let mask: String?
        let status: String?
        let type: String?
        let useDhcp: Bool?

        enum CodingKeys: String, CodingKey {
            case ifname, ip, mask, status, type
            case useDhcp = "use_dhcp"
        }
    }

    enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case gateway
        case dnsPrimary = "dns_primary"
        case dnsSecondary = "dns_secondary"
        case dnsManual = "dns_manual"
        case v6gateway
        case enableWinDomain = "enable_windomain"
        case gatewayInfo = "gateway_info"
    }
}
