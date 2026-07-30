//
//  DSMParameter.swift
//  dsmaccess
//
//  Safe encoding of the complex parameters the DSM WebAPIs expect.
//

import Foundation

/// A DSM parameter value before it is encoded according to the `requestFormat` advertised
/// by `SYNO.API.Info`. Keeping the type avoids sending booleans and numbers as strings when
/// the API expects JSON values.
enum DSMParameter: Sendable, ExpressibleByStringLiteral {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case json(String)

    init(stringLiteral value: String) {
        self = .string(value)
    }

    static func json<Value: Encodable>(_ value: Value) throws -> DSMParameter {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw DSMError.decoding(detail: nil)
        }
        return .json(string)
    }

    func encoded(for requestFormat: String?) throws -> String {
        guard requestFormat?.uppercased() == "JSON" else {
            return switch self {
            case .string(let value), .json(let value): value
            case .integer(let value): String(value)
            case .boolean(let value): value ? "true" : "false"
            }
        }

        switch self {
        case .string(let value):
            let data = try JSONEncoder().encode(value)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw DSMError.decoding(detail: nil)
            }
            return encoded
        case .integer(let value):
            return String(value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .json(let value):
            return value
        }
    }
}
