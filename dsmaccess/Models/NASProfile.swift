//
//  NASProfile.swift
//  dsmaccess
//
//  Non-secret metadata of a saved NAS.
//

import Foundation

nonisolated struct NASProfile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var connection: NASConnectionTarget
    var account: String
    var remembersPassword: Bool

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        useHTTPS: Bool,
        account: String,
        remembersPassword: Bool
    ) {
        self.id = id
        self.name = name
        self.connection = .direct(DSMEndpoint(
            useHTTPS: useHTTPS,
            host: host,
            port: port
        ))
        self.account = account
        self.remembersPassword = remembersPassword
    }

    init(
        id: UUID = UUID(),
        name: String,
        connection: NASConnectionTarget,
        account: String,
        remembersPassword: Bool
    ) {
        self.id = id
        self.name = name
        self.connection = connection
        self.account = account
        self.remembersPassword = remembersPassword
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? connection.defaultProfileName : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case connection
        case account
        case remembersPassword
        case host
        case port
        case useHTTPS
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        account = try container.decode(String.self, forKey: .account)
        remembersPassword = try container.decodeIfPresent(
            Bool.self,
            forKey: .remembersPassword
        ) ?? false

        if let savedConnection = try container.decodeIfPresent(
            NASConnectionTarget.self,
            forKey: .connection
        ) {
            connection = savedConnection
        } else {
            connection = .direct(DSMEndpoint(
                useHTTPS: try container.decode(Bool.self, forKey: .useHTTPS),
                host: try container.decode(String.self, forKey: .host),
                port: try container.decode(Int.self, forKey: .port)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(connection, forKey: .connection)
        try container.encode(account, forKey: .account)
        try container.encode(remembersPassword, forKey: .remembersPassword)
    }
}
