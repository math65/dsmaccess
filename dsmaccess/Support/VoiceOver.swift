//
//  VoiceOver.swift
//  dsmaccess
//
//  Annonces VoiceOver centralisées. Deux raffinements par rapport à un `.post()` direct :
//  un léger délai qui évite que l'annonce soit « avalée » quand l'écran change au même
//  instant, et une priorité de parole (file d'attente vs interruption).
//

import SwiftUI

enum VoiceOver {
    /// Priorité de l'annonce : `.low` s'insère dans la file, `.high` interrompt la parole en cours.
    enum Priority {
        case low, normal, high
    }

    /// Poste une annonce VoiceOver après un court délai, avec la priorité demandée.
    @MainActor
    static func announce(_ message: String, priority: Priority = .normal) {
        var text = AttributedString(message)
        switch priority {
        case .low: text.accessibilitySpeechAnnouncementPriority = .low
        case .normal: text.accessibilitySpeechAnnouncementPriority = .default
        case .high: text.accessibilitySpeechAnnouncementPriority = .high
        }
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
