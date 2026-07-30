//
//  NASConnectionTarget.swift
//  dsmaccess
//
//  Stable identity used to find a NAS again along with its associated secrets.
//

import Foundation

nonisolated enum NASConnectionTarget: Codable, Equatable, Sendable {
    case direct(DSMEndpoint)
    case quickConnect(id: String)

    private enum Kind: String, Codable {
        case direct
        case quickConnect
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case useHTTPS
        case host
        case port
        case quickConnectID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .direct:
            self = .direct(DSMEndpoint(
                useHTTPS: try container.decode(Bool.self, forKey: .useHTTPS),
                host: try container.decode(String.self, forKey: .host),
                port: try container.decode(Int.self, forKey: .port)
            ))
        case .quickConnect:
            self = .quickConnect(
                id: try container.decode(String.self, forKey: .quickConnectID)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .direct(let endpoint):
            try container.encode(Kind.direct, forKey: .kind)
            try container.encode(endpoint.useHTTPS, forKey: .useHTTPS)
            try container.encode(endpoint.host, forKey: .host)
            try container.encode(endpoint.port, forKey: .port)
        case .quickConnect(let id):
            try container.encode(Kind.quickConnect, forKey: .kind)
            try container.encode(id, forKey: .quickConnectID)
        }
    }

    var directEndpoint: DSMEndpoint? {
        guard case .direct(let endpoint) = self else { return nil }
        return endpoint
    }

    var defaultProfileName: String {
        switch self {
        case .direct(let endpoint): endpoint.host
        case .quickConnect(let id): id
        }
    }

    func credentialStoreKey(account: String) -> String {
        switch self {
        case .direct(let endpoint):
            endpoint.credentialStoreKey(account: account)
        case .quickConnect(let id):
            "\(account)@quickconnect://\(id.lowercased())"
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.direct(let lhsEndpoint), .direct(let rhsEndpoint)):
            lhsEndpoint == rhsEndpoint
        case (.quickConnect(let lhsID), .quickConnect(let rhsID)):
            lhsID.caseInsensitiveCompare(rhsID) == .orderedSame
        default:
            false
        }
    }
}
