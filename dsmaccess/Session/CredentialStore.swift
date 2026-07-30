//
//  CredentialStore.swift
//  dsmaccess
//
//  Password storage for automatic reconnection ("Stay signed in").
//  The password rests in the Keychain (encrypted); a non-secret flag
//  (`Preferences.rememberPassword`) says whether the option is on. Passwords and device
//  tokens are kept separate per account and per stable NAS identity.
//

import Foundation

enum CredentialStore {
    private static func legacyKey(account: String, endpoint: DSMEndpoint) -> String {
        "\(account)@\(endpoint.host):\(endpoint.port)"
    }

    /// Stores the password and turns automatic reconnection on.
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

    /// Reads the password stored for this NAS (nil if there is none).
    static func password(account: String, target: NASConnectionTarget) -> String? {
        load(service: KeychainStore.passwordService, account: account, target: target)
    }

    /// Forgets the password and turns automatic reconnection off.
    static func forget(account: String, target: NASConnectionTarget) {
        delete(service: KeychainStore.passwordService, account: account, target: target)
        Preferences.rememberPassword = false
    }

    /// Stores the open session so it can be resumed on the next launch. The CSRF token goes
    /// along with the SID: without it, a resumed session would be refused with 119.
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

    /// Session stored for this NAS, if there is one. Its validity can only be known by trying
    /// it: DSM announces no expiry date.
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

        // The old keys did not record the scheme. They are only migrated to HTTPS so that an
        // existing secret cannot be picked up over HTTP.
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
