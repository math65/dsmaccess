//
//  Preferences.swift
//  dsmaccess
//
//  Préférences persistantes (valeurs NON secrètes) au-dessus de UserDefaults.
//  Un accès typé par réglage : `Preferences.lastHost` en lecture comme en écriture,
//  le nom de clé n'est écrit qu'une seule fois (dans `Key`) pour éviter les fautes.
//  Les secrets (mot de passe, jeton d'appareil) ne passent JAMAIS par ici → voir KeychainStore.
//

import Foundation

enum Preferences {
    private static let defaults = UserDefaults.standard

    /// Noms de clés bruts : une seule source de vérité, partagée entre get et set.
    private enum Key {
        static let lastHost = "lastHost"
        static let lastPort = "lastPort"
        static let lastUseHTTPS = "lastUseHTTPS"
        static let lastAccount = "lastAccount"
        static let rememberPassword = "rememberPassword"
    }

    /// Dernière adresse (hôte) du NAS saisie au login.
    static var lastHost: String {
        get { defaults.string(forKey: Key.lastHost) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastHost) }
    }

    /// Dernier port utilisé ; `nil` = retomber sur le port par défaut du schéma (HTTP/HTTPS).
    /// On passe par `object(forKey:)` (et non `integer(forKey:)`) car ce dernier
    /// renvoie 0 quand la clé est absente, ce qui écraserait la distinction « pas de port mémorisé ».
    static var lastPort: Int? {
        get { defaults.object(forKey: Key.lastPort) as? Int }
        set { defaults.set(newValue, forKey: Key.lastPort) }
    }

    /// Dernier choix HTTPS.
    static var lastUseHTTPS: Bool {
        get {
            guard defaults.object(forKey: Key.lastUseHTTPS) != nil else { return true }
            return defaults.bool(forKey: Key.lastUseHTTPS)
        }
        set { defaults.set(newValue, forKey: Key.lastUseHTTPS) }
    }

    /// Dernier nom de compte.
    static var lastAccount: String {
        get { defaults.string(forKey: Key.lastAccount) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastAccount) }
    }

    /// L'utilisateur a demandé « Rester connecté » : le mot de passe est mémorisé au
    /// Trousseau et l'app tente une reconnexion automatique au lancement.
    static var rememberPassword: Bool {
        get { defaults.bool(forKey: Key.rememberPassword) }
        set { defaults.set(newValue, forKey: Key.rememberPassword) }
    }
}
