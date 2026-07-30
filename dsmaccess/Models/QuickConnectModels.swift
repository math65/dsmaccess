//
//  QuickConnectModels.swift
//  dsmaccess
//
//  Format of the commands and responses of the QuickConnect resolution service.
//

import Foundation

nonisolated struct QuickConnectControlCommand: Encodable, Sendable {
    enum Command: String, Encodable, Sendable {
        case getServerInfo = "get_server_info"
        case requestTunnel = "request_tunnel"
    }

    let version = 1
    let command: Command
    let stopWhenError: Bool
    let stopWhenSuccess: Bool
    let id = "mainapp_https"
    let serverID: String
    let isGofile = false
    let path = "/"

    enum CodingKeys: String, CodingKey {
        case version, command, id, serverID, path
        case stopWhenError = "stop_when_error"
        case stopWhenSuccess = "stop_when_success"
        case isGofile = "is_gofile"
    }
}

nonisolated struct QuickConnectControlResponse: Decodable, Sendable {
    struct Server: Decodable, Sendable {
        let serverID: String
        let pingpongPath: String?

        enum CodingKeys: String, CodingKey {
            case serverID
            case pingpongPath = "pingpong_path"
        }
    }

    struct Service: Decodable, Sendable {
        let port: Int
        let externalPort: Int
        let relayIP: String?
        let relayPort: Int?
        /// Relay host name supplied by QuickConnect (e.g. `synr-xx.ID.direct.quickconnect.to`).
        let relayDN: String?

        enum CodingKeys: String, CodingKey {
            case port
            case externalPort = "ext_port"
            case relayIP = "relay_ip"
            case relayPort = "relay_port"
            case relayDN = "relay_dn"
        }
    }

    struct Environment: Decodable, Sendable {
        let controlHost: String
        let relayRegion: String

        enum CodingKeys: String, CodingKey {
            case controlHost = "control_host"
            case relayRegion = "relay_region"
        }
    }

    struct SmartDNS: Decodable, Sendable {
        let lan: [String]
        let lanIPv6: [String]
        let host: String?

        enum CodingKeys: String, CodingKey {
            case lan
            case lanIPv6 = "lanv6"
            case host
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            lan = try container.decodeIfPresent([String].self, forKey: .lan) ?? []
            lanIPv6 = try container.decodeIfPresent([String].self, forKey: .lanIPv6) ?? []
            host = try container.decodeIfPresent(String.self, forKey: .host)
        }
    }

    let errno: Int
    let suberrno: Int?
    let server: Server?
    let service: Service?
    let environment: Environment?
    let smartDNS: SmartDNS?

    enum CodingKeys: String, CodingKey {
        case errno, suberrno, server, service
        case environment = "env"
        case smartDNS = "smartdns"
    }
}

nonisolated struct QuickConnectPingResponse: Decodable, Sendable {
    let ezid: String
}
