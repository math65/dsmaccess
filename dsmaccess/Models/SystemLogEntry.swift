//
//  SystemLogEntry.swift
//  dsmaccess
//
//  Entrées du journal DSM et adresses bloquées par les protections de connexion.
//

import Foundation

struct SystemLogEntry: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let timestamp: String?
    let level: String
    let category: String?
    let user: String?
    let address: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp = "time"
        case alternateTimestamp = "timestamp"
        case level
        case priority
        case category
        case type
        case user
        case who
        case address = "from"
        case ip
        case message
        case event
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = values.flexString(.timestamp) ?? values.flexString(.alternateTimestamp)
        level = values.flexString(.level) ?? values.flexString(.priority) ?? "info"
        category = values.flexString(.category) ?? values.flexString(.type)
        user = values.flexString(.user) ?? values.flexString(.who)
        address = values.flexString(.address) ?? values.flexString(.ip)
        message = values.flexString(.message) ?? values.flexString(.event) ?? ""
        id = values.flexString(.id) ?? "\(timestamp ?? ""):\(message.hashValue)"
    }
}

struct SystemLogList: Decodable, Sendable {
    let logs: [SystemLogEntry]

    enum CodingKeys: String, CodingKey { case logs, items }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        logs = (try? values.decode([SystemLogEntry].self, forKey: .logs))
            ?? (try? values.decode([SystemLogEntry].self, forKey: .items))
            ?? []
    }
}

struct BlockedAddress: Decodable, Identifiable, Hashable, Sendable {
    let address: String
    let createdAt: String?
    let expiresAt: String?
    let reason: String?

    var id: String { address }

    enum CodingKeys: String, CodingKey {
        case address = "ip"
        case alternateAddress = "address"
        case host
        case createdAt = "create_time"
        case alternateCreatedAt = "created_at"
        case expiresAt = "expire_time"
        case alternateExpiresAt = "expires_at"
        case reason
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        address = values.flexString(.address)
            ?? values.flexString(.alternateAddress)
            ?? values.flexString(.host)
            ?? ""
        createdAt = values.flexString(.createdAt) ?? values.flexString(.alternateCreatedAt)
        expiresAt = values.flexString(.expiresAt) ?? values.flexString(.alternateExpiresAt)
        reason = values.flexString(.reason)
    }
}

struct BlockedAddressList: Decodable, Sendable {
    let addresses: [BlockedAddress]

    enum CodingKeys: String, CodingKey {
        case addresses = "block_list"
        case items
        case hosts
        case data
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        addresses = (try? values.decode([BlockedAddress].self, forKey: .addresses))
            ?? (try? values.decode([BlockedAddress].self, forKey: .items))
            ?? (try? values.decode([BlockedAddress].self, forKey: .hosts))
            ?? (try? values.decode([BlockedAddress].self, forKey: .data))
            ?? []
    }
}
