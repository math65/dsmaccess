//
//  SecureSignIn.swift
//  dsmaccess
//
//  Passwordless DSM sign-in: approval request sent to the Synology Secure SignIn mobile
//  app, then waiting for the user's decision.
//

import Foundation

/// Approval request accepted by the NAS. The NAS only attaches a `verifyNumber` about one
/// time in two: when it is there, the user has to recognize that number on their phone,
/// otherwise a simple tap is enough.
struct SecureSignInRequest: Equatable, Sendable {
    let requestID: String
    let verifyNumber: Int?
}

/// State of a request, as the NAS reports it as long as it has not been decided.
enum SecureSignInStatus: Equatable, Sendable {
    case waiting(verifyNumber: Int?)
    case approved(token: String)
    case denied
    case expired
    case revoked

    var isWaiting: Bool {
        if case .waiting = self { return true }
        return false
    }
}

/// Outcome decided on the NAS or phone side. Each case carries its own message: "denied"
/// and "expired" do not call for the same reaction from the user.
enum SecureSignInRefusal: Error {
    case denied
    case expired
    case revoked

    var message: String {
        switch self {
        case .denied:
            String(localized: "secure_signin.error.denied")
        case .expired:
            String(localized: "secure_signin.error.expired")
        case .revoked:
            String(localized: "secure_signin.error.cancelled")
        }
    }
}

/// The approval request is no longer valid. DSM answers 400 to the login carrying it, where
/// that same code means "credentials refused" on the classic path: without that distinction,
/// an expired request would blame the user for a password mistake.
struct SecureSignInExpired: Error {}

struct SecureSignInRequestPayload: nonisolated Decodable, Sendable {
    let requestID: String
    let requestStatus: String?
    let verifyNumber: Int?

    private enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case requestStatus = "request_status"
        case verifyNumber = "verify_number"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.requiredFlexString(.requestID)
        requestStatus = container.flexString(.requestStatus)
        verifyNumber = container.flexInt(.verifyNumber)
    }
}

struct SecureSignInStatusPayload: nonisolated Decodable, Sendable {
    let status: String
    let token: String?
    let verifyNumber: Int?

    private enum CodingKeys: String, CodingKey {
        case status, token
        case verifyNumber = "verify_number"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.requiredFlexString(.status)
        token = container.flexString(.token)
        verifyNumber = container.flexInt(.verifyNumber)
    }

    /// The states DSM reports. "corrupted" signals a damaged installation of the Secure
    /// SignIn package on the NAS side: treated as a denial, with its own message.
    var resolved: SecureSignInStatus? {
        switch status {
        case "waiting": .waiting(verifyNumber: verifyNumber)
        case "approved": token.flatMap { $0.isEmpty ? nil : .approved(token: $0) }
        case "denied", "corrupted": .denied
        case "timeout": .expired
        case "revoked": .revoked
        default: nil
        }
    }
}
