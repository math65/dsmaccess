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
    /// Réponse illisible (JSON non décodable).
    case decoding
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
    /// Autre erreur API renvoyée par DSM.
    case apiError(code: Int)
    /// Échec d'une opération groupée avec le détail du premier élément refusé par DSM.
    case itemOperationFailed(code: Int, item: String?, itemCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return String(localized: "Adresse du NAS invalide.")
        case .network(let detail):
            return String(localized: "Impossible de joindre le NAS : \(detail)")
        case .untrustedCertificate:
            return String(localized: "Le certificat de sécurité de ce NAS n'est pas approuvé.")
        case .decoding:
            return String(localized: "La réponse du NAS n'a pas pu être lue.")
        case .invalidResponse:
            return String(localized: "Réponse inattendue du NAS.")
        case .cancelled:
            return String(localized: "Requête annulée.")
        case .unsupportedAPI(let name):
            return String(localized: "Cette fonctionnalité n'est pas disponible sur ce NAS (API \(name)).")
        case .unsupportedAPIVersion(let name):
            return String(localized: "La version DSM installée ne prend pas en charge cette fonctionnalité (API \(name)).")
        case .sessionExpired:
            return String(localized: "La session a expiré. Reconnectez-vous au NAS.")
        case .invalidCredentials:
            return String(localized: "Nom d'utilisateur ou mot de passe incorrect.")
        case .accountDisabled:
            return String(localized: "Ce compte est désactivé.")
        case .permissionDenied:
            return String(localized: "Permission refusée pour ce compte.")
        case .needsOTP:
            return String(localized: "Un code de vérification à deux facteurs est requis.")
        case .badOTP:
            return String(localized: "Code de vérification incorrect. Réessayez.")
        case .otpEnforced:
            return String(localized: "La double authentification est obligatoire pour ce compte. Activez-la dans DSM.")
        case .apiError(let code):
            return String(localized: "Erreur du NAS (code \(code)).")
        case .itemOperationFailed(let code, let item?, let itemCode):
            return String(localized: "Échec de l’opération sur « \(item) » (codes \(code) et \(itemCode)).")
        case .itemOperationFailed(let code, nil, let itemCode):
            return String(localized: "Échec de l’opération sur un élément (codes \(code) et \(itemCode)).")
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
