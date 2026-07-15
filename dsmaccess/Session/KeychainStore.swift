//
//  KeychainStore.swift
//  dsmaccess
//
//  Petit utilitaire de stockage sécurisé (Trousseau) pour les secrets durables,
//  en premier lieu le jeton d'appareil (device token) qui évite de ressaisir le
//  code de vérification à chaque connexion.
//

import Foundation
import Security

enum KeychainStore {
    /// Service utilisé pour les jetons d'appareil DSM.
    static let deviceTokenService = "math65.dsmaccess.deviceToken"
    /// Service utilisé pour les mots de passe mémorisés (reconnexion automatique).
    static let passwordService = "math65.dsmaccess.password"
    /// Service utilisé pour les empreintes des certificats explicitement approuvés.
    static let serverTrustService = "math65.dsmaccess.serverTrust"

    /// Enregistre (ou remplace) une valeur pour un couple service/compte.
    @discardableResult
    static func save(_ value: String, service: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // On supprime l'éventuelle entrée existante puis on ré-insère (upsert simple).
        SecItemDelete(base as CFDictionary)
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// Lit une valeur pour un couple service/compte, ou nil si absente.
    static func load(service: String, account: String) -> String? {
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

    /// Supprime une valeur pour un couple service/compte.
    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
