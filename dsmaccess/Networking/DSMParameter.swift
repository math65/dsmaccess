//
//  DSMParameter.swift
//  dsmaccess
//
//  Encodage sûr des paramètres complexes attendus par les WebAPI DSM.
//

import Foundation

enum DSMParameter {
    static func json<Value: Encodable>(_ value: Value) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw DSMError.decoding
        }
        return string
    }
}
