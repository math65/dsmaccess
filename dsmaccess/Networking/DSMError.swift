//
//  DSMError.swift
//  dsmaccess
//
//  Network/API layer errors, with ready-to-display French messages
//  (also meant to be read aloud by VoiceOver).
//

import Foundation

enum DSMError: Error, LocalizedError, Equatable {
    /// Invalid NAS address (URL cannot be built).
    case invalidEndpoint
    /// Network problem (unreachable host, timeout, rejected certificate…).
    case network(String)
    /// Self-signed or untrusted certificate that requires an explicit decision.
    case untrustedCertificate(fingerprint: String)
    /// Unreadable response (JSON cannot be decoded). `detail` describes the failure in terms
    /// of fields and path, without any value: it feeds the report.
    case decoding(detail: String?)
    /// Unexpected HTTP response.
    case invalidResponse
    /// Cancelled request (view left / request replaced) — to be ignored, not a real failure.
    case cancelled
    /// The API is not exposed by this NAS, or the matching package is not installed.
    case unsupportedAPI(String)
    /// The versions exposed by the NAS do not meet the needs of this feature.
    case unsupportedAPIVersion(String)
    /// The DSM session no longer exists or has been invalidated.
    case sessionExpired
    /// Incorrect credentials (code 400).
    case invalidCredentials
    /// Disabled account (code 401).
    case accountDisabled
    /// Permission denied (code 402).
    case permissionDenied
    /// Two-factor verification code required (code 403).
    case needsOTP
    /// Incorrect verification code (code 404).
    case badOTP
    /// Two-factor authentication is mandatory and must be enabled on the account (code 406).
    case otpEnforced
    /// DSM requires a new password before opening the session (code 410): happens after a
    /// reset by the administrator when the NAS enforces the change.
    case passwordMustChange
    /// The password does not satisfy the strength rules configured on the NAS.
    case weakPassword
    /// The account was indeed created, but adding it to the requested groups failed: the
    /// operation can neither be presented as successful, nor retried as is.
    case userCreatedWithoutGroups(name: String)
    /// Any other API error returned by DSM.
    case apiError(code: Int)
    /// Package Center requires a decision or a wizard that the app must not guess.
    case packageCenter(String)
    /// Failure of a batch operation, with the detail of the first item DSM rejected.
    case itemOperationFailed(code: Int, item: String?, itemCode: Int)

    /// A resumed session is only validated by an authenticated call. These particular refusals
    /// come from the NAS **after** it has identified us: they prove the session is alive,
    /// unlike a network incident, which proves nothing.
    var provesSessionIsAlive: Bool {
        switch self {
        case .permissionDenied, .unsupportedAPI, .unsupportedAPIVersion, .apiError:
            true
        default:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return String(localized: "error.address.invalid")
        case .network(let detail):
            return String(localized: "error.network.unreachable", defaultValue: "Unable to reach the NAS: \(detail)")
        case .untrustedCertificate:
            return String(localized: "error.certificate.untrusted")
        case .decoding:
            return String(localized: "error.response.unreadable")
        case .invalidResponse:
            return String(localized: "error.response.unexpected")
        case .cancelled:
            return String(localized: "error.request.cancelled")
        case .unsupportedAPI(let name):
            return String(localized: "error.api.unavailable", defaultValue: "This feature is not available on this NAS (API \(name)).")
        case .unsupportedAPIVersion(let name):
            return String(localized: "error.api.version_unsupported", defaultValue: "The installed DSM version does not support this feature (API \(name)).")
        case .sessionExpired:
            return String(localized: "error.session.expired")
        case .invalidCredentials:
            return String(localized: "error.auth.invalid_credentials")
        case .accountDisabled:
            return String(localized: "error.auth.account_disabled")
        case .permissionDenied:
            return String(localized: "error.auth.permission_denied")
        case .needsOTP:
            return String(localized: "error.auth.otp_required")
        case .badOTP:
            return String(localized: "error.auth.invalid_otp")
        case .otpEnforced:
            return String(localized: "error.auth.otp_enforced")
        case .passwordMustChange:
            return String(localized: "common.error.password_change_required")
        case .weakPassword:
            return String(localized: "error.password.policy_rejected")
        case .userCreatedWithoutGroups(let name):
            return String(localized: "error.user.created_without_groups", defaultValue: "The account \(name) was created, but adding it to the groups failed.")
        case .apiError(let code):
            return String(localized: "error.nas.code", defaultValue: "NAS error (code \(code)).")
        case .packageCenter(let message):
            return message
        case .itemOperationFailed(let code, let item?, let itemCode):
            return String(localized: "error.operation.named_failed", defaultValue: "The operation on “\(item)” failed (codes \(code) and \(itemCode)).")
        case .itemOperationFailed(let code, nil, let itemCode):
            return String(localized: "error.operation.item_failed", defaultValue: "An item operation failed (codes \(code) and \(itemCode)).")
        }
    }

    /// “Definitive” account-related failure: no point retrying with the same password
    /// (used to decide whether to forget a stored password during an automatic reconnection).
    var isCredentialFailure: Bool {
        switch self {
        case .invalidCredentials, .accountDisabled, .permissionDenied, .otpEnforced:
            return true
        default:
            return false
        }
    }

    /// True if the error is only a cancellation (task interrupted because the view was left
    /// or the request replaced). To be handled silently: no message, no announcement.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        if case DSMError.cancelled = error { return true }
        return false
    }
}
