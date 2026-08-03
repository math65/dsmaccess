//
//  DSMJSONValue.swift
//  dsmaccess
//
//  A DSM payload the app passes through without modelling it.
//

import Foundation

/// JSON of an arbitrary shape, kept as received. Used where a payload must survive a round
/// trip untouched — a Package Center dependency tree, a container creation profile — because
/// modelling only the known fields would drop whatever DSM adds that this app does not know.
enum DSMJSONValue: Codable, Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([DSMJSONValue])
    case object([String: DSMJSONValue])

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([DSMJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: DSMJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Package Center JSON value."
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .boolean(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var hasContent: Bool {
        switch self {
        case .null:
            false
        case .string(let value):
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let value):
            !value.isEmpty
        case .object(let value):
            !value.isEmpty
        case .boolean, .integer, .number:
            true
        }
    }
}
