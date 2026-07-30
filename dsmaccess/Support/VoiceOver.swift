//
//  VoiceOver.swift
//  dsmaccess
//
//  Centralised VoiceOver announcements. Rapid announcements are grouped into a single
//  speech request; the requests that follow use the native macOS low priority so they
//  wait for the speech in progress to finish.
//

import AppKit

enum VoiceOver {
    @MainActor private static var pendingAnnouncement: Task<Void, Never>?
    @MainActor private static var queuedMessages = [String]()
    @MainActor private static var queuedBatchTask: Task<Void, Never>?

    /// Announcement priority: `.low` slots into the queue, `.high` interrupts speech in progress.
    enum Priority {
        case low, normal, high
    }

    /// Posts a VoiceOver announcement after a short delay, with the requested priority.
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
    static func announce(
        _ outcome: DSMOperationOutcome,
        priority: Priority = .normal,
        onSuccess: () -> Void = { }
    ) {
        switch outcome {
        case .success(let message):
            onSuccess()
            announce(message, category: .result, priority: priority)
        case .failure(let message):
            announce(message, category: .error, priority: priority)
        case .cancelled:
            break
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

    /// A single notification cannot interrupt one of its own sentences.
    /// Grouping therefore protects the quick "loading" then "result" pairs.
    static func combinedQueuedMessage(_ messages: [String]) -> String {
        messages.joined(separator: " ")
    }

    /// SwiftUI can lose the VoiceOver target when a loading state is replaced.
    /// Waits for the hierarchy to update, then fixes only a focus captured by a
    /// toolbar control. The toolbar itself stays a navigable stop.
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
            guard let accessibleElement = element as? NSAccessibilityProtocol else { return false }
            if accessibleElement.accessibilityRole() == .toolbar {
                return !isFocusedElement
            }
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
