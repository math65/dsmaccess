//
//  StoredDSMSession.swift
//  dsmaccess
//
//  DSM session kept between two launches, so the app reopens without going back through the
//  login screen. No expiration date appears here: DSM does not announce one, and an invented
//  date would either throw away a still-valid session, or keep a dead one. Only a real
//  attempt settles it.
//

import Foundation

nonisolated struct StoredDSMSession: Codable, Equatable, Sendable {
    /// Session identifier. Bearer secret: Keychain only, never logged.
    let sid: String
    /// Associated anti-CSRF token. Without it, DSM refuses the resumed session with 119.
    let synoToken: String?

    init(sid: String, synoToken: String?) {
        self.sid = sid
        self.synoToken = synoToken
    }

    init?(_ result: LoginResult) {
        guard !result.sid.isEmpty else { return nil }
        self.init(sid: result.sid, synoToken: result.synotoken)
    }
}
