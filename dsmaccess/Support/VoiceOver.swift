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
    @MainActor private static var pendingAnnouncement: Task<Void, Never>?
    @MainActor private static var queuedAnnouncements = [AttributedString]()
    @MainActor private static var queueTask: Task<Void, Never>?

    /// Priorité de l'annonce : `.low` s'insère dans la file, `.high` interrompt la parole en cours.
    enum Priority {
        case low, normal, high
    }

    /// Poste une annonce VoiceOver après un court délai, avec la priorité demandée.
    @MainActor
    static func announce(
        _ message: String,
        category: AnnouncementCategory = .result,
        priority: Priority = .normal
    ) {
        guard Preferences.enabledAnnouncementCategories.contains(category) else { return }
        var text = AttributedString(message)
        if Preferences.queueAnnouncements {
            // Une priorité basse demande au système de lire cette annonce après celles
            // déjà en cours, plutôt que d'interrompre la parole VoiceOver.
            text.accessibilitySpeechAnnouncementPriority = .low
            pendingAnnouncement?.cancel()
            pendingAnnouncement = nil
            queuedAnnouncements.append(text)
            startQueueIfNeeded()
            return
        }

        queueTask?.cancel()
        queueTask = nil
        queuedAnnouncements.removeAll()
        pendingAnnouncement?.cancel()
        switch priority {
        case .low: text.accessibilitySpeechAnnouncementPriority = .low
        case .normal: text.accessibilitySpeechAnnouncementPriority = .default
        case .high: text.accessibilitySpeechAnnouncementPriority = .high
        }
        pendingAnnouncement = Task {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(text).post()
            pendingAnnouncement = nil
        }
    }

    @MainActor
    private static func startQueueIfNeeded() {
        guard queueTask == nil else { return }
        queueTask = Task {
            while !queuedAnnouncements.isEmpty {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let next = queuedAnnouncements.removeFirst()
                AccessibilityNotification.Announcement(next).post()
            }
            queueTask = nil
        }
    }
}
