//
//  Preferences.swift
//  dsmaccess
//
//  Persistent preferences (NON-secret values) on top of UserDefaults.
//  One typed accessor per setting: `Preferences.lastHost` for both reading and writing,
//  the key name is written only once (in `Key`) to avoid typos.
//  Secrets (password, device token) NEVER go through here → see KeychainStore.
//

import Foundation

enum Preferences {
    private static let defaults = UserDefaults.standard

    /// Raw key names: a single source of truth, shared between get and set.
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
        static let notifiesFinishedOperations = "notifiesFinishedOperations"
        static let playsCompletionSound = "playsCompletionSound"
        static let authenticationMethod = "authenticationMethod"
        static let sidebarOrder = "sidebarOrder"
        static let enabledSidebarModules = "enabledSidebarModules"
        static let knownSidebarModules = "knownSidebarModules"
        static let automaticallyHideUnavailableModules = "automaticallyHideUnavailableModules"
        static let appBackendInstallID = "appBackendInstallID"
        static let seenBackendAnnouncementIDs = "appBackendSeenAnnouncementIDs"
        static let feedbackEmail = "feedbackEmail"
    }

    /// Last NAS address (host) entered at login.
    static var lastHost: String {
        get { defaults.string(forKey: Key.lastHost) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastHost) }
    }

    /// Last port used; `nil` = fall back to the scheme's default port (HTTP/HTTPS).
    /// We go through `object(forKey:)` (and not `integer(forKey:)`) because the latter
    /// returns 0 when the key is absent, which would erase the "no port stored" distinction.
    static var lastPort: Int? {
        get { defaults.object(forKey: Key.lastPort) as? Int }
        set { defaults.set(newValue, forKey: Key.lastPort) }
    }

    /// Last HTTPS choice.
    static var lastUseHTTPS: Bool {
        get {
            guard defaults.object(forKey: Key.lastUseHTTPS) != nil else { return true }
            return defaults.bool(forKey: Key.lastUseHTTPS)
        }
        set { defaults.set(newValue, forKey: Key.lastUseHTTPS) }
    }

    /// Last account name.
    static var lastAccount: String {
        get { defaults.string(forKey: Key.lastAccount) ?? "" }
        set { defaults.set(newValue, forKey: Key.lastAccount) }
    }

    /// The user asked to "Stay signed in": the password is stored in the Keychain and the
    /// app attempts an automatic reconnection at launch.
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

    /// System notification at the end of a long operation. On by default: it only fires when
    /// the app is not frontmost, and macOS keeps control through its own setting.
    static var notifiesFinishedOperations: Bool {
        get {
            guard defaults.object(forKey: Key.notifiesFinishedOperations) != nil else { return true }
            return defaults.bool(forKey: Key.notifiesFinishedOperations)
        }
        set { defaults.set(newValue, forKey: Key.notifiesFinishedOperations) }
    }

    /// Short sound at the end of a long operation, when the app is frontmost. On by default:
    /// it doubles the VoiceOver announcement for someone looking elsewhere on screen, and
    /// says nothing on its own. When not frontmost, the notification takes over.
    static var playsCompletionSound: Bool {
        get {
            guard defaults.object(forKey: Key.playsCompletionSound) != nil else { return true }
            return defaults.bool(forKey: Key.playsCompletionSound)
        }
        set { defaults.set(newValue, forKey: Key.playsCompletionSound) }
    }

    /// Last authentication mode chosen on the sign-in screen. An unknown value (a setting
    /// written by a future version) falls back to the password, which is always offered.
    static var authenticationMethod: ConnectionViewModel.AuthenticationMethod {
        get {
            guard let raw = defaults.string(forKey: Key.authenticationMethod),
                  let method = ConnectionViewModel.AuthenticationMethod(rawValue: raw) else {
                return .password
            }
            return method
        }
        set { defaults.set(newValue.rawValue, forKey: Key.authenticationMethod) }
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

    /// Anonymous install identifier for backend announcements, generated on first access
    /// then stable. The server only stores a hash of it, to deduplicate the reach counter
    /// of an announcement.
    static var appBackendInstallID: String {
        if let existing = defaults.string(forKey: Key.appBackendInstallID), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: Key.appBackendInstallID)
        return fresh
    }

    /// Identifiers of `once` announcements already shown (the server always returns the
    /// active announcement; the "only once" rule is applied on the client side).
    static var seenBackendAnnouncementIDs: [String] {
        get { defaults.stringArray(forKey: Key.seenBackendAnnouncementIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.seenBackendAnnouncementIDs) }
    }

    /// Email address from the contact form, stored after a successful send.
    static var feedbackEmail: String {
        get { defaults.string(forKey: Key.feedbackEmail) ?? "" }
        set { defaults.set(newValue, forKey: Key.feedbackEmail) }
    }
}
