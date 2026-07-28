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

    /// Vrai si le NAS expose la connexion sans mot de passe. Le compte, lui, peut ne pas
    /// l'avoir activée : cela ne se sait qu'en demandant l'approbation.
    var supportsSecureSignIn: Bool {
        transport.capabilities.supports(Self.secureSignInAPI)
    }

    /// Demande une approbation dans l'app mobile Synology. Le NAS envoie la notification
    /// dès cet appel ; il ne renvoie pas encore de session.
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

    /// Interroge la décision de l'utilisateur. Accessible sans session : c'est le propre
    /// de cette étape, qui précède l'ouverture de la session.
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

    /// Échange le jeton d'approbation contre une session.
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

    /// Annule une demande laissée en attente, pour que le NAS n'expose pas indéfiniment
    /// une approbation dont l'app ne veut plus.
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

    /// Les trois étapes passent par le même appel de login, seuls `action`, `request_id`
    /// et `authenticator_token` changent. Le mot de passe reste vide : c'est tout l'objet
    /// de cette connexion. Contrat relevé sur DSM 7.4 ; les champs partent en clair, le
    /// chiffrement du portail web n'étant pas exigé par l'API. Ni `format` ni
    /// `enable_syno_token` ne sont joints : le NAS renvoie déjà le SID et le jeton CSRF
    /// sans eux, et ce chemin n'a été éprouvé que sous cette forme.
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
            // Sur ce chemin, 400 rapporte une demande d'approbation périmée, pas un
            // identifiant refusé : aucun mot de passe n'a été envoyé.
            if response.error?.code == 400 { throw SecureSignInExpired() }
            throw loginError(code: response.error?.code)
        }
        return value
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
