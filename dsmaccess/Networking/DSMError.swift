//
//  DSMError.swift
//  dsmaccess
//
//  Erreurs de la couche réseau/API, avec messages en français prêts à afficher
//  (et à faire lire par VoiceOver).
//

import Foundation

enum DSMError: Error, LocalizedError, Equatable {
    /// Adresse du NAS invalide (URL non construisible).
    case invalidEndpoint
    /// Problème réseau (hôte injoignable, délai dépassé, certificat refusé…).
    case network(String)
    /// Certificat auto-signé ou non approuvé qui nécessite une décision explicite.
    case untrustedCertificate(fingerprint: String)
    /// Réponse illisible (JSON non décodable). `detail` décrit l'échec en termes de
    /// champs et de chemin, sans aucune valeur : il alimente le signalement.
    case decoding(detail: String?)
    /// Réponse HTTP inattendue.
    case invalidResponse
    /// Requête annulée (vue quittée / requête remplacée) — à ignorer, pas un vrai échec.
    case cancelled
    /// L'API n'est pas exposée par ce NAS ou le paquet correspondant n'est pas installé.
    case unsupportedAPI(String)
    /// Les versions exposées par le NAS ne satisfont pas les besoins de cette fonctionnalité.
    case unsupportedAPIVersion(String)
    /// La session DSM n'existe plus ou a été invalidée.
    case sessionExpired
    /// Identifiants incorrects (code 400).
    case invalidCredentials
    /// Compte désactivé (code 401).
    case accountDisabled
    /// Permission refusée (code 402).
    case permissionDenied
    /// Code de vérification à deux facteurs requis (code 403).
    case needsOTP
    /// Code de vérification incorrect (code 404).
    case badOTP
    /// Double authentification obligatoire à activer côté compte (code 406).
    case otpEnforced
    /// DSM exige un nouveau mot de passe avant d'ouvrir la session (code 410) : arrive après
    /// une réinitialisation par l'administrateur quand le NAS impose le changement.
    case passwordMustChange
    /// Le mot de passe ne satisfait pas les règles de force configurées sur le NAS.
    case weakPassword
    /// Le compte a bien été créé, mais son ajout aux groupes demandés a échoué : l'opération
    /// ne peut être ni présentée comme réussie, ni retentée à l'identique.
    case userCreatedWithoutGroups(name: String)
    /// Autre erreur API renvoyée par DSM.
    case apiError(code: Int)
    /// Le Centre de paquets exige une décision ou un assistant que l'app ne doit pas deviner.
    case packageCenter(String)
    /// Échec d'une opération groupée avec le détail du premier élément refusé par DSM.
    case itemOperationFailed(code: Int, item: String?, itemCode: Int)

    /// Une session reprise n'est validée que par un appel authentifié. Ces refus-là
    /// viennent du NAS **après** nous avoir identifiés : ils prouvent que la session vit,
    /// contrairement à un incident réseau, qui ne prouve rien.
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

    /// Échec « définitif » lié au compte : inutile de retenter avec le même mot de passe
    /// (sert à décider d'oublier un mot de passe mémorisé lors d'une reconnexion auto).
    var isCredentialFailure: Bool {
        switch self {
        case .invalidCredentials, .accountDisabled, .permissionDenied, .otpEnforced:
            return true
        default:
            return false
        }
    }

    /// Vrai si l'erreur n'est qu'une annulation (tâche interrompue parce que la vue a été
    /// quittée ou la requête remplacée). À traiter silencieusement : ni message, ni annonce.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        if case DSMError.cancelled = error { return true }
        return false
    }
}
