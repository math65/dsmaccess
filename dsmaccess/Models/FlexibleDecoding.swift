//
//  FlexibleDecoding.swift
//  dsmaccess
//
//  Décodage défensif des valeurs DSM dont le type JSON varie selon la version.
//

import Foundation

extension KeyedDecodingContainer {
    nonisolated func flexInt(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return Int(exactly: value) }
        if let value = try? decode(Double.self, forKey: key) {
            return Int(exactly: value.rounded())
        }
        if let value = try? decode(String.self, forKey: key) {
            if let integer = Int(value) { return integer }
            if let number = Double(value) { return Int(exactly: number.rounded()) }
        }
        return nil
    }

    nonisolated func flexInt64(_ key: Key) -> Int64? {
        if let value = try? decode(Int64.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Int64(value) }
        if let value = try? decode(Double.self, forKey: key) {
            return Int64(exactly: value.rounded())
        }
        if let value = try? decode(String.self, forKey: key) {
            if let integer = Int64(value) { return integer }
            if let number = Double(value) { return Int64(exactly: number.rounded()) }
        }
        return nil
    }

    nonisolated func flexDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    nonisolated func flexBool(_ key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = flexInt(key) { return value != 0 }
        if let value = try? decode(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "yes", "on", "enabled": return true
            case "false", "no", "off", "disabled": return false
            default: return nil
            }
        }
        return nil
    }

    nonisolated func flexString(_ key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }

    nonisolated func requiredFlexString(_ key: Key) throws -> String {
        guard let value = flexString(key), !value.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Required DSM identifier is missing or malformed."
            )
        }
        return value
    }

    nonisolated func requiredFlexInt(_ key: Key) throws -> Int {
        guard let value = flexInt(key) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Required DSM integer is missing or malformed."
            )
        }
        return value
    }

    nonisolated func requiredFlexBool(_ key: Key) throws -> Bool {
        guard let value = flexBool(key) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Required DSM Boolean is missing or malformed."
            )
        }
        return value
    }

    /// Décode le premier alias présent. Une clé absente signifie « aucune donnée » ;
    /// une clé présente mais mal formée reste une erreur de schéma et n'est jamais
    /// transformée en collection vide.
    nonisolated func decodeArray<Element: Decodable>(
        _ type: Element.Type,
        forFirstPresent keys: [Key]
    ) throws -> [Element] {
        for key in keys where contains(key) {
            return try decodeIfPresent([Element].self, forKey: key) ?? []
        }
        return []
    }
}
