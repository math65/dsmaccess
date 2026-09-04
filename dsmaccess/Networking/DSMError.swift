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
    /// The account was indeed created, but DSM refused these groups: the operation can neither
    /// be presented as successful, nor retried as is. The groups are named because the others
    /// were applied, and the user has to know which ones are left to assign by hand.
    case userCreatedWithoutGroups(name: String, groups: [String])
    /// DSM refused these group changes on an existing account. The changes it accepted stand.
    case membershipsRefused(groups: [String])
    /// A group by that name already exists on the NAS.
    case groupNameTaken(name: String)
    /// Any other API error returned by DSM. `message` carries the explanation DSM attached to
    /// the code, when it attached one: the NAS sends it already localized where it has a
    /// translation, and the web client displays it as it arrives.
    case apiError(code: Int, message: String?)
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
        case .userCreatedWithoutGroups(let name, let groups):
            let list = groups.formatted(.list(type: .and))
            return String(localized: "error.user.created_without_groups", defaultValue: "The account \(name) was created, but the NAS refused these groups: \(list).")
        case .membershipsRefused(let groups):
            let list = groups.formatted(.list(type: .and))
            return String(localized: "error.user.memberships_refused", defaultValue: "The NAS refused these groups: \(list). The other changes were applied.")
        case .groupNameTaken(let name):
            return String(localized: "error.group.name_taken", defaultValue: "A group named \(name) already exists. Choose another name.")
        case .apiError(let code, let message?):
            return String(localized: "error.nas.code_explained", defaultValue: "NAS error (code \(code.errorCodeText)): \(message)")
        case .apiError(let code, _):
            return String(localized: "error.nas.code", defaultValue: "NAS error (code \(code.errorCodeText)).")
        case .packageCenter(let message):
            return message
        case .itemOperationFailed(let code, let item?, let itemCode) where code == itemCode:
            return String(localized: "error.operation.named_failed_one_code", defaultValue: "The operation on “\(item)” failed (code \(code.errorCodeText)).")
        case .itemOperationFailed(let code, let item?, let itemCode):
            return String(localized: "error.operation.named_failed", defaultValue: "The operation on “\(item)” failed (codes \(code.errorCodeText) and \(itemCode.errorCodeText)).")
        case .itemOperationFailed(let code, nil, let itemCode) where code == itemCode:
            return String(localized: "error.operation.failed_one_code", defaultValue: "The operation failed (code \(code.errorCodeText)).")
        case .itemOperationFailed(let code, nil, let itemCode):
            return String(localized: "error.operation.item_failed", defaultValue: "The operation failed (codes \(code.errorCodeText) and \(itemCode.errorCodeText)).")
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

extension Int {
    /// A DSM code identifies a failure; it is not a quantity. Interpolated as an integer into
    /// a localized string it picks up the locale's grouping separator — 4562 is displayed as
    /// “4 562”, VoiceOver reads it as a number, and it no longer matches the code DSM itself
    /// documents.
    nonisolated var errorCodeText: String { formatted(.number.grouping(.never)) }
}
