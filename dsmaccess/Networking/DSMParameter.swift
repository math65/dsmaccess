//
//  DSMParameter.swift
//  dsmaccess
//
//  Encodage sûr des paramètres complexes attendus par les WebAPI DSM.
//

import Foundation

/// Valeur de paramètre DSM avant son encodage selon le `requestFormat` annoncé
/// par `SYNO.API.Info`. Conserver le type évite d'envoyer des booléens et nombres
/// comme des chaînes lorsque l'API attend des valeurs JSON.
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
            throw DSMError.decoding
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
                throw DSMError.decoding
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
