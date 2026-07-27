//
//  DSMAuthenticationService.swift
//  dsmaccess
//
//  Ouverture et fermeture d'une session DSM, y compris OTP, jeton d'appareil et CSRF.
//

import Foundation

@MainActor
final class DSMAuthenticationService {
    // DSM 7.4 accorde aux sessions ouvertes en v6 des droits réduits : les mutations de
    // SYNO.Core.User/Group échouent en 402 même pour un administrateur. Le login v7 obtient
    // une session complète ; les NAS plus anciens retombent sur leur version maximale.
    private static let api = DSMAPI("SYNO.API.Auth", preferredVersion: 7, minimumVersion: 3)
    // « reset » n'existe pas avant la v6 de SYNO.API.Auth : contrat relevé sur DSM 7.4.
    private static let resetAPI = DSMAPI("SYNO.API.Auth", preferredVersion: 6, minimumVersion: 6)

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
        // Pas de paramètre « session » : DSM le traite comme une application soumise au
        // contrôle de privilèges. Un nom qui ne correspond à aucune application installée
        // passe pour un administrateur mais fait échouer tout compte standard en 402.
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

    /// Nouveau mot de passe exigé par DSM avant l'ouverture de session (login en 410).
    /// L'appel se fait hors session, avec l'ancien mot de passe comme preuve d'identité.
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
        case let code?: .apiError(code: code)
        case nil: .invalidResponse
        }
    }
}
