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
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        // Updated in place rather than deleted then added: a failure between the two would
        // lose the stored secret, and with it the session or the approved certificate.
        let updateStatus = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecItemNotFound else {
            return updateStatus == errSecSuccess
        }
        let newItem = base.merging(attributes) { current, _ in current }
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
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
