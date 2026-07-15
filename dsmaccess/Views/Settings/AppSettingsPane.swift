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

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .announcements: "Annonces"
        case .sidebar: "Barre latérale"
        case .nas: "NAS"
        }
    }

    var localizedTitle: String {
        switch self {
        case .announcements: String(localized: "Annonces")
        case .sidebar: String(localized: "Barre latérale")
        case .nas: String(localized: "NAS")
        }
    }

    var systemImage: String {
        switch self {
        case .announcements: "speaker.wave.2"
        case .sidebar: "sidebar.left"
        case .nas: "externaldrive.connected.to.line.below"
        }
    }

    var help: LocalizedStringKey {
        switch self {
        case .announcements: "Configurer les annonces VoiceOver"
        case .sidebar: "Configurer les modules de la barre latérale"
        case .nas: "Gérer les NAS enregistrés"
        }
    }
}
