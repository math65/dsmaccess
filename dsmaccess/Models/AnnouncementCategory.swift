//
//  AnnouncementCategory.swift
//  dsmaccess
//
//  Catégories d'annonces configurables dans les réglages d'accessibilité.
//

import Foundation

enum AnnouncementCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case navigation
    case progress
    case result
    case error
    case automaticRefresh

    var id: Self { self }

    var title: String {
        switch self {
        case .navigation: String(localized: "announcements.category.navigation.title")
        case .progress: String(localized: "announcements.category.progress.title")
        case .result: String(localized: "announcements.category.result.title")
        case .error: String(localized: "common.level.errors")
        case .automaticRefresh: String(localized: "common.label.automatic_refresh")
        }
    }

    var detail: String {
        switch self {
        case .navigation: String(localized: "announcements.category.navigation.description")
        case .progress: String(localized: "announcements.category.progress.description")
        case .result: String(localized: "announcements.category.result.description")
        case .error: String(localized: "announcements.category.error.description")
        case .automaticRefresh: String(localized: "announcements.category.auto_refresh.description")
        }
    }
}
