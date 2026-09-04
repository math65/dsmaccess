//
//  DSMAuthenticationService.swift
//  dsmaccess
//
//  Opening and closing a DSM session, including OTP, device token and CSRF.
//

import Foundation

@MainActor
final class DSMAuthenticationService {
    // DSM 7.4 grants reduced rights to sessions opened in v6: SYNO.Core.User/Group mutations
    // fail with 402 even for an administrator. The v7 login gets a full session; older NAS
    // fall back to their highest supported version.
    private static let api = DSMAPI("SYNO.API.Auth", preferredVersion: 7, minimumVersion: 3)
    // "reset" does not exist before v6 of SYNO.API.Auth: contract captured on DSM 7.4.
    private static let resetAPI = DSMAPI("SYNO.API.Auth", preferredVersion: 6, minimumVersion: 6)
    private static let secureSignInAPI = DSMAPI(
        "SYNO.SecureSignIn.Authenticator.Request",
        preferredVersion: 1,
        minimumVersion: 1
    )

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func login(
        account: String,
        password: String,
        otpCode: String?,
        deviceID: String?,
        rememberDevice: Bool
    ) async throws -> LoginResult {
        // No "session" parameter: DSM treats it as an application subject to privilege
        // control. A name matching no installed application goes through for an administrator
        // but makes every standard account fail with 402.
        var parameters: [String: DSMParameter] = [
            "account": .string(account),
            "passwd": .string(password),
            "format": .string("sid"),
            "enable_syno_token": .string("yes"),
        ]
        if let otpCode, !otpCode.isEmpty {
            parameters["otp_code"] = .string(otpCode)
        }
        if let deviceID, !deviceID.isEmpty {
            parameters["device_id"] = .string(deviceID)
        }
        if rememberDevice {
            parameters["enable_device_token"] = .string("yes")
            parameters["device_name"] = .string("DSM Access (Mac)")
        }

        let response = try await transport.response(
            api: Self.api,
            method: "login",
            parameters: parameters,
            authenticated: false,
            requestPolicy: .idempotent,
            as: LoginResult.self
        )
        guard response.success, let result = response.data else {
            throw loginError(code: response.error?.code)
        }
        transport.establishSession(result)
        return result
    }

    /// True if the NAS exposes passwordless sign-in. The account itself may not have enabled
    /// it: that is only known by requesting the approval.
    var supportsSecureSignIn: Bool {
        transport.capabilities.supports(Self.secureSignInAPI)
    }

    /// Requests an approval in the Synology mobile app. The NAS sends the notification as
    /// soon as this call is made; it does not return a session yet.
    func requestSecureSignIn(account: String, rememberDevice: Bool) async throws -> SecureSignInRequest {
        let payload = try await sendSecureSignInLogin(
            account: account,
            action: "get_status",
            requestID: "",
            token: "",
            rememberDevice: rememberDevice,
            as: SecureSignInRequestPayload.self
        )
        return SecureSignInRequest(
            requestID: payload.requestID,
            verifyNumber: payload.verifyNumber
        )
    }

    /// Polls the user's decision. Reachable without a session: that is the very nature of
    /// this step, which comes before the session is opened.
    func secureSignInStatus(
        account: String,
        requestID: String
    ) async throws -> SecureSignInStatus {
        let payload = try await transport.read(
            api: Self.secureSignInAPI,
            method: "status",
            parameters: [
                "account": .string(account),
                "request_id": .string(requestID),
            ],
            authenticated: false,
            as: SecureSignInStatusPayload.self
        )
        guard let status = payload.resolved else { throw DSMError.invalidResponse }
        return status
    }

    /// Exchanges the approval token for a session.
    func completeSecureSignIn(
        account: String,
        requestID: String,
        token: String,
        rememberDevice: Bool
    ) async throws -> LoginResult {
        let result = try await sendSecureSignInLogin(
            account: account,
            action: "approved",
            requestID: requestID,
            token: token,
            rememberDevice: rememberDevice,
            as: LoginResult.self
        )
        transport.establishSession(result)
        return result
    }

    /// Cancels a request left pending, so the NAS does not keep offering indefinitely an
    /// approval the app no longer wants.
    func revokeSecureSignIn(account: String, requestID: String) async {
        try? await transport.perform(
            api: Self.secureSignInAPI,
            method: "revoke",
            parameters: [
                "account": .string(account),
                "request_id": .string(requestID),
            ],
            authenticated: false
        )
    }

    /// The three steps go through the same login call, only `action`, `request_id` and
    /// `authenticator_token` change. The password stays empty: that is the whole point of
    /// this sign-in. Contract captured on DSM 7.4; the fields are sent in clear, the web
    /// portal's encryption not being required by the API. Neither `format` nor
    /// `enable_syno_token` is attached: the NAS already returns the SID and the CSRF token
    /// without them, and this path has only ever been proven in this form.
    private func sendSecureSignInLogin<Value: Decodable & Sendable>(
        account: String,
        action: String,
        requestID: String,
        token: String,
        rememberDevice: Bool,
        as type: Value.Type
    ) async throws -> Value {
        var parameters: [String: DSMParameter] = [
            "account": .string(account),
            "passwd": .string(""),
            "authenticator_token": .string(token),
            "logintype": .string("local"),
            "type": .string("authenticator"),
            "application": .string("DSM"),
            "request_id": .string(requestID),
            "action": .string(action),
        ]
        if rememberDevice {
            parameters["enable_device_token"] = .string("yes")
            parameters["device_name"] = .string("DSM Access (Mac)")
        }

        let response = try await transport.response(
            api: Self.api,
            method: "login",
            parameters: parameters,
            authenticated: false,
            httpMethod: .post,
            as: type
        )
        guard response.success, let value = response.data else {
            // On this path, 400 reports an expired approval request, not rejected
            // credentials: no password was sent.
            if response.error?.code == 400 { throw SecureSignInExpired() }
            throw loginError(code: response.error?.code)
        }
        return value
    }

    /// New password required by DSM before the session can open (login returning 410).
    /// The call is made outside a session, with the old password as proof of identity.
    func resetPassword(account: String, currentPassword: String, newPassword: String) async throws {
        try await transport.perform(
            api: Self.resetAPI,
            method: "reset",
            parameters: [
                "account": .string(account),
                "passwd": .string(currentPassword),
                "new_passwd": .string(newPassword),
            ],
            authenticated: false
        )
    }

    func logout() async {
        defer { transport.clearSession() }
        try? await transport.perform(api: Self.api, method: "logout")
    }

    private func loginError(code: Int?) -> DSMError {
        switch code {
        case 400: .invalidCredentials
        case 401: .accountDisabled
        case 402: .permissionDenied
        case 403: .needsOTP
        case 404: .badOTP
        case 406: .otpEnforced
        case 410: .passwordMustChange
        case let code?: .apiError(code: code, message: nil)
        case nil: .invalidResponse
        }
    }
}
