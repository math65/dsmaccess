//
//  AppSettingsPane.swift
//  dsmaccess
//
//  Sections of the Settings window.
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
        case .announcements: "settings.tab.announcements"
        case .sidebar: "common.label.sidebar"
        case .nas: "common.label.nas"
        case .updates: "common.label.updates"
        }
    }

    var localizedTitle: String {
        switch self {
        case .announcements: String(localized: "settings.tab.announcements")
        case .sidebar: String(localized: "common.label.sidebar")
        case .nas: String(localized: "common.label.nas")
        case .updates: String(localized: "common.label.updates")
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
        case .announcements: String(localized: "settings.tab.announcements.hint")
        case .sidebar: String(localized: "settings.tab.modules.hint")
        case .nas: String(localized: "settings.tab.nas.hint")
        case .updates: String(localized: "settings.tab.updates.hint")
        }
    }
}
