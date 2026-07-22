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
        static let nasProfiles = "nasProfiles"
        static let selectedNASProfileID = "selectedNASProfileID"
        static let enabledAnnouncementCategories = "enabledAnnouncementCategories"
        static let queueAnnouncements = "queueAnnouncements"
        static let sidebarOrder = "sidebarOrder"
        static let enabledSidebarModules = "enabledSidebarModules"
        static let knownSidebarModules = "knownSidebarModules"
        static let automaticallyHideUnavailableModules = "automaticallyHideUnavailableModules"
        static let appBackendInstallID = "appBackendInstallID"
        static let seenBackendAnnouncementIDs = "appBackendSeenAnnouncementIDs"
        static let feedbackEmail = "feedbackEmail"
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

    static var nasProfiles: [NASProfile] {
        get {
            guard let data = defaults.data(forKey: Key.nasProfiles),
                  let profiles = try? JSONDecoder().decode([NASProfile].self, from: data) else {
                return []
            }
            return profiles
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.nasProfiles)
        }
    }

    static var selectedNASProfileID: UUID? {
        get {
            defaults.string(forKey: Key.selectedNASProfileID).flatMap(UUID.init(uuidString:))
        }
        set { defaults.set(newValue?.uuidString, forKey: Key.selectedNASProfileID) }
    }

    static var enabledAnnouncementCategories: Set<AnnouncementCategory> {
        get {
            guard let values = defaults.stringArray(forKey: Key.enabledAnnouncementCategories) else {
                return Set(AnnouncementCategory.allCases)
            }
            return Set(values.compactMap(AnnouncementCategory.init(rawValue:)))
        }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.enabledAnnouncementCategories) }
    }

    static var queueAnnouncements: Bool {
        get {
            guard defaults.object(forKey: Key.queueAnnouncements) != nil else { return true }
            return defaults.bool(forKey: Key.queueAnnouncements)
        }
        set { defaults.set(newValue, forKey: Key.queueAnnouncements) }
    }

    static var sidebarOrder: [AppModule] {
        get {
            let saved = defaults.stringArray(forKey: Key.sidebarOrder) ?? []
            let restored = saved.compactMap(AppModule.init(rawValue:))
            return restored + AppModule.allCases.filter { !restored.contains($0) }
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Key.sidebarOrder) }
    }

    static var enabledSidebarModules: Set<AppModule> {
        get {
            guard let values = defaults.stringArray(forKey: Key.enabledSidebarModules) else {
                defaults.set(AppModule.allCases.map(\.rawValue), forKey: Key.knownSidebarModules)
                return Set(AppModule.allCases)
            }
            var enabled = Set(values.compactMap(AppModule.init(rawValue:)))
            let knownValues = defaults.stringArray(forKey: Key.knownSidebarModules)
            let newlyIntroduced: Set<AppModule>
            if let knownValues {
                let known = Set(knownValues.compactMap(AppModule.init(rawValue:)))
                newlyIntroduced = Set(AppModule.allCases).subtracting(known)
            } else {
                newlyIntroduced = [.usbCopy]
            }
            enabled.formUnion(newlyIntroduced)
            defaults.set(enabled.map(\.rawValue).sorted(), forKey: Key.enabledSidebarModules)
            defaults.set(AppModule.allCases.map(\.rawValue), forKey: Key.knownSidebarModules)
            return enabled
        }
        set {
            defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.enabledSidebarModules)
            defaults.set(AppModule.allCases.map(\.rawValue), forKey: Key.knownSidebarModules)
        }
    }

    static var automaticallyHideUnavailableModules: Bool {
        get {
            guard defaults.object(forKey: Key.automaticallyHideUnavailableModules) != nil else {
                return true
            }
            return defaults.bool(forKey: Key.automaticallyHideUnavailableModules)
        }
        set { defaults.set(newValue, forKey: Key.automaticallyHideUnavailableModules) }
    }

    /// Identifiant d'installation anonyme pour les annonces du backend, généré au
    /// premier accès puis stable. Le serveur n'en stocke qu'un hachage, pour
    /// dédupliquer le compteur de portée d'une annonce.
    static var appBackendInstallID: String {
        if let existing = defaults.string(forKey: Key.appBackendInstallID), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Key.appBackendInstallID)
        return fresh
    }

    /// Identifiants des annonces `once` déjà affichées (le serveur renvoie toujours
    /// l'annonce active ; le « une seule fois » est appliqué côté client).
    static var seenBackendAnnouncementIDs: [String] {
        get { defaults.stringArray(forKey: Key.seenBackendAnnouncementIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.seenBackendAnnouncementIDs) }
    }

    /// Adresse e-mail du formulaire de contact, mémorisée après un envoi réussi.
    static var feedbackEmail: String {
        get { defaults.string(forKey: Key.feedbackEmail) ?? "" }
        set { defaults.set(newValue, forKey: Key.feedbackEmail) }
    }
}
