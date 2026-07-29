//
//  CredentialStore.swift
//  dsmaccess
//
//  Mémorisation du mot de passe pour la reconnexion automatique (« Rester connecté »).
//  Le mot de passe dort dans le Trousseau (chiffré) ; un indicateur non secret
//  (`Preferences.rememberPassword`) dit si l'option est active. Les mots de passe et
//  jetons d'appareil sont séparés par compte et identité stable du NAS.
//

import Foundation

enum CredentialStore {
    private static func legacyKey(account: String, endpoint: DSMEndpoint) -> String {
        "\(account)@\(endpoint.host):\(endpoint.port)"
    }

    /// Mémorise le mot de passe et active la reconnexion automatique.
    @discardableResult
    static func remember(
        password: String,
        account: String,
        target: NASConnectionTarget
    ) -> Bool {
        let saved = save(password, service: KeychainStore.passwordService,
                         account: account, target: target)
        Preferences.rememberPassword = saved
        return saved
    }

    /// Lit le mot de passe mémorisé pour ce NAS (nil si aucun).
    static func password(account: String, target: NASConnectionTarget) -> String? {
        load(service: KeychainStore.passwordService, account: account, target: target)
    }

    /// Oublie le mot de passe et désactive la reconnexion automatique.
    static func forget(account: String, target: NASConnectionTarget) {
        delete(service: KeychainStore.passwordService, account: account, target: target)
        Preferences.rememberPassword = false
    }

    /// Mémorise la session ouverte pour la reprendre au prochain lancement. Le jeton CSRF
    /// accompagne le SID : sans lui, une session reprise se ferait refuser en 119.
    @discardableResult
    static func rememberSession(
        _ session: StoredDSMSession,
        account: String,
        target: NASConnectionTarget
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(session),
              let encoded = String(data: data, encoding: .utf8) else { return false }
        return save(encoded, service: KeychainStore.sessionService,
                    account: account, target: target)
    }

    /// Session mémorisée pour ce NAS, si elle existe. Sa validité ne se sait qu'en
    /// l'essayant : DSM n'annonce aucune date d'expiration.
    static func session(account: String, target: NASConnectionTarget) -> StoredDSMSession? {
        guard let stored = load(service: KeychainStore.sessionService,
                                account: account, target: target),
              let data = stored.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StoredDSMSession.self, from: data)
    }

    static func forgetSession(account: String, target: NASConnectionTarget) {
        delete(service: KeychainStore.sessionService, account: account, target: target)
    }

    static func deviceID(account: String, target: NASConnectionTarget) -> String? {
        load(service: KeychainStore.deviceTokenService, account: account, target: target)
    }

    @discardableResult
    static func remember(
        deviceID: String,
        account: String,
        target: NASConnectionTarget
    ) -> Bool {
        save(deviceID, service: KeychainStore.deviceTokenService,
             account: account, target: target)
    }

    private static func save(
        _ value: String,
        service: String,
        account: String,
        target: NASConnectionTarget
    ) -> Bool {
        let saved = KeychainStore.save(
            value,
            service: service,
            account: target.credentialStoreKey(account: account)
        )
        if saved, let endpoint = target.directEndpoint, endpoint.useHTTPS {
            KeychainStore.delete(
                service: service,
                account: legacyKey(account: account, endpoint: endpoint)
            )
        }
        return saved
    }

    private static func load(
        service: String,
        account: String,
        target: NASConnectionTarget
    ) -> String? {
        let key = target.credentialStoreKey(account: account)
        if let value = KeychainStore.load(service: service, account: key) {
            return value
        }

        // Les anciennes clés n'indiquaient pas le schéma. Elles ne sont migrées que
        // vers HTTPS afin qu'un secret existant ne puisse pas être repris en HTTP.
        guard let endpoint = target.directEndpoint,
              endpoint.useHTTPS,
              let value = KeychainStore.load(
                  service: service,
                  account: legacyKey(account: account, endpoint: endpoint)
              ) else { return nil }
        if KeychainStore.save(value, service: service, account: key) {
            KeychainStore.delete(
                service: service,
                account: legacyKey(account: account, endpoint: endpoint)
            )
        }
        return value
    }

    private static func delete(
        service: String,
        account: String,
        target: NASConnectionTarget
    ) {
        KeychainStore.delete(
            service: service,
            account: target.credentialStoreKey(account: account)
        )
        if let endpoint = target.directEndpoint, endpoint.useHTTPS {
            KeychainStore.delete(
                service: service,
                account: legacyKey(account: account, endpoint: endpoint)
            )
        }
    }
}
