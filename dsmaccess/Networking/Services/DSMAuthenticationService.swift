//
//  DSMAuthenticationService.swift
//  dsmaccess
//
//  Ouverture et fermeture d'une session DSM, y compris OTP, jeton d'appareil et CSRF.
//

import Foundation

@MainActor
final class DSMAuthenticationService {
    private static let api = DSMAPI("SYNO.API.Auth", preferredVersion: 6, minimumVersion: 3)
    private static let sessionName = "DSMAccess"

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
        var parameters: [String: DSMParameter] = [
            "account": .string(account),
            "passwd": .string(password),
            "session": .string(Self.sessionName),
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
            as: LoginResult.self
        )
        guard response.success, let result = response.data else {
            throw loginError(code: response.error?.code)
        }
        transport.establishSession(result)
        return result
    }

    func logout() async {
        defer { transport.clearSession() }
        try? await transport.perform(
            api: Self.api,
            method: "logout",
            parameters: ["session": .string(Self.sessionName)]
        )
    }

    private func loginError(code: Int?) -> DSMError {
        switch code {
        case 400: .invalidCredentials
        case 401: .accountDisabled
        case 402: .permissionDenied
        case 403: .needsOTP
        case 404: .badOTP
        case 406: .otpEnforced
        case let code?: .apiError(code: code)
        case nil: .invalidResponse
        }
    }
}
