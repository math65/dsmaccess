//
//  VoiceOver.swift
//  dsmaccess
//
//  Annonces VoiceOver centralisées. Les annonces rapides sont regroupées en une seule
//  demande de parole ; les demandes suivantes utilisent la priorité basse native de
//  macOS pour attendre la fin de la parole en cours.
//

import AppKit

enum VoiceOver {
    @MainActor private static var pendingAnnouncement: Task<Void, Never>?
    @MainActor private static var queuedMessages = [String]()
    @MainActor private static var queuedBatchTask: Task<Void, Never>?

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
        if Preferences.queueAnnouncements {
            pendingAnnouncement?.cancel()
            pendingAnnouncement = nil
            queuedMessages.append(message)
            scheduleQueuedBatch()
            return
        }

        queuedBatchTask?.cancel()
        queuedBatchTask = nil
        queuedMessages.removeAll()
        pendingAnnouncement?.cancel()
        pendingAnnouncement = Task {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            post(message, priority: priority)
            pendingAnnouncement = nil
        }
    }

    @MainActor
    private static func scheduleQueuedBatch() {
        queuedBatchTask?.cancel()
        queuedBatchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard !Task.isCancelled, !queuedMessages.isEmpty else { return }
            let message = combinedQueuedMessage(queuedMessages)
            queuedMessages.removeAll()
            post(message, priority: .low)
            queuedBatchTask = nil
        }
    }

    /// Une seule notification ne peut pas interrompre l'une de ses propres phrases.
    /// Le regroupement protège donc les paires rapides « chargement » puis « résultat ».
    static func combinedQueuedMessage(_ messages: [String]) -> String {
        messages.joined(separator: " ")
    }

    /// SwiftUI peut perdre la cible VoiceOver quand un état de chargement est remplacé.
    /// Attend la mise à jour de la hiérarchie, puis corrige uniquement un focus capturé
    /// par un contrôle de la barre d'outils. La barre elle-même reste une étape navigable.
    @MainActor
    static func restoreFocusIfCapturedByToolbar(_ restore: () -> Void) async {
        await Task.yield()
        guard !Task.isCancelled, focusedElementIsToolbarDescendant else { return }
        restore()
    }

    @MainActor
    private static func post(_ message: String, priority: Priority) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.accessibilityPriority.rawValue
            ]
        )
    }

    @MainActor
    private static var focusedElementIsToolbarDescendant: Bool {
        var element: Any? = NSApp.accessibilityFocusedUIElement
        var isFocusedElement = true
        for _ in 0..<12 {
            guard let object = element as? NSObject else { return false }
            if object.value(forKey: "accessibilityRole") as? NSAccessibility.Role == .toolbar {
                return !isFocusedElement
            }
            guard let accessibleElement = object as? NSAccessibilityElement else { return false }
            element = accessibleElement.accessibilityParent()
            isFocusedElement = false
        }
        return false
    }
}

private extension VoiceOver.Priority {
    var accessibilityPriority: NSAccessibilityPriorityLevel {
        switch self {
        case .low: .low
        case .normal: .medium
        case .high: .high
        }
    }
}
