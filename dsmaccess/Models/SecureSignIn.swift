//
//  SecureSignIn.swift
//  dsmaccess
//
//  Connexion sans mot de passe DSM : demande d'approbation envoyée à l'app mobile
//  Synology Secure SignIn, puis attente de la décision de l'utilisateur.
//

import Foundation

/// Demande d'approbation acceptée par le NAS. Le NAS ne joint un `verifyNumber` qu'une
/// fois sur deux environ : quand il est là, l'utilisateur doit reconnaître ce chiffre
/// sur son téléphone, sinon un simple appui suffit.
struct SecureSignInRequest: Equatable, Sendable {
    let requestID: String
    let verifyNumber: Int?
}

/// État d'une demande, tel que le NAS le rapporte tant qu'elle n'est pas tranchée.
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

/// Fin de partie décidée côté NAS ou téléphone. Chaque cas porte son message : « refusée »
/// et « expirée » n'appellent pas la même réaction de l'utilisateur.
enum SecureSignInRefusal: Error {
    case denied
    case expired
    case revoked

    var message: String {
        switch self {
        case .denied:
            String(localized: "Connexion refusée depuis l’app Synology Secure SignIn.")
        case .expired:
            String(localized: "La demande d’approbation a expiré. Relancez la connexion.")
        case .revoked:
            String(localized: "La demande d’approbation a été annulée.")
        }
    }
}

/// La demande d'approbation n'est plus valable. DSM répond 400 au login qui la porte, là
/// où ce même code signifie « identifiants refusés » sur le chemin classique : sans cette
/// distinction, une demande expirée accuserait l'utilisateur d'une faute de mot de passe.
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

    /// Les états rapportés par DSM. « corrupted » signale une installation abîmée du
    /// paquet Secure SignIn côté NAS : traité comme un refus, avec son propre message.
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
