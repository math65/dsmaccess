//
//  LoginResult.swift
//  dsmaccess
//
//  Payload returned by SYNO.API.Auth (method=login) on success.
//

import Foundation

/// Result of a successful login.
struct LoginResult: nonisolated Decodable, Sendable {
    /// Session identifier to attach (`_sid=`) to every subsequent request.
    let sid: String
    /// Device token returned when asking to "remember this device".
    /// Long-lived secret: to be stored in the Keychain, never in the clear.
    let did: String?
    /// Optional anti-CSRF token.
    let synotoken: String?
}
