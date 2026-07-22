//
//  AppSettingsPane.swift
//  dsmaccess
//
//  Sections de la fenêtre Réglages.
//

import SwiftUI

enum AppSettingsPane: String, CaseIterable, Identifiable {
    case announcements
    case sidebar
    case nas
    case updates

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .announcements: "Annonces"
        case .sidebar: "Barre latérale"
        case .nas: "NAS"
        case .updates: "Mises à jour"
        }
    }

    var localizedTitle: String {
        switch self {
        case .announcements: String(localized: "Annonces")
        case .sidebar: String(localized: "Barre latérale")
        case .nas: String(localized: "NAS")
        case .updates: String(localized: "Mises à jour")
        }
    }

    var systemImage: String {
        switch self {
        case .announcements: "speaker.wave.2"
        case .sidebar: "sidebar.left"
        case .nas: "externaldrive.connected.to.line.below"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    var localizedHelp: String {
        switch self {
        case .announcements: String(localized: "Configurer les annonces VoiceOver")
        case .sidebar: String(localized: "Configurer les modules de la barre latérale")
        case .nas: String(localized: "Gérer les NAS enregistrés")
        case .updates: String(localized: "Configurer les mises à jour de DSM Access")
        }
    }
}
