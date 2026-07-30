//
//  KeychainStore.swift
//  dsmaccess
//
//  Small secure-storage helper (Keychain) for durable secrets, first of all the device
//  token that avoids re-entering the verification code on every sign-in.
//

import Foundation
import Security

enum KeychainStore {
    /// Service used for DSM device tokens.
    nonisolated static let deviceTokenService = "math65.dsmaccess.deviceToken"
    /// Service used for remembered passwords (automatic reconnection).
    nonisolated static let passwordService = "math65.dsmaccess.password"
    /// Service used for the fingerprints of explicitly approved certificates.
    nonisolated static let serverTrustService = "math65.dsmaccess.serverTrust"
    /// Service used for the DSM session kept between two launches. A session identifier opens
    /// the NAS to whoever holds it: it is protected like a password.
    nonisolated static let sessionService = "math65.dsmaccess.session"

    /// Stores (or replaces) a value for a service/account pair.
    @discardableResult
    nonisolated static func save(_ value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Delete any existing entry, then re-insert (simple upsert).
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Reads a value for a service/account pair, or nil if absent.
    nonisolated static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Deletes a value for a service/account pair.
    nonisolated static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
