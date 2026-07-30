//
//  BackendAnnouncementCoordinator.swift
//  dsmaccess
//
//  Checks at launch whether the backend has a publisher message to display, and
//  applies the "once only" mode on the client side (the server always returns the
//  active announcement). Network failure is silent: this service is optional and
//  must never get in the way of startup.
//
//  Presentation goes through NSAlert and not SwiftUI's `.alert` modifier:
//  permanently attached to the root, the latter makes the window's accessibility
//  audit fail (inconsistent parent/child hierarchy), whereas NSAlert is read in
//  full by VoiceOver and handles the keyboard natively.
//

import AppKit

final class BackendAnnouncementCoordinator {
    /// Announcement held by `checkAtLaunch`, to be presented via `presentPendingAnnouncement`.
    /// Kept separate from presentation so it stays testable without a user interface.
    private(set) var pendingAnnouncement: AppBackendClient.Announcement?

    private let client: AppBackendClient
    private var didCheck = false

    init(client: AppBackendClient = AppBackendClient()) {
        self.client = client
    }

    func checkAtLaunch() async {
        guard !didCheck else { return }
        didCheck = true
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true ? "fr" : "en"
        guard let announcement = try? await client.checkAnnouncement(
            installID: Preferences.appBackendInstallID,
            language: language
        ) else {
            return
        }
        if announcement.mode == "once", Preferences.seenBackendAnnouncementIDs.contains(announcement.id) {
            return
        }
        pendingAnnouncement = announcement
    }

    /// Displays the pending announcement in a modal alert, then confirms the
    /// display to the backend and counts any activation of the link button.
    func presentPendingAnnouncement() {
        guard let announcement = pendingAnnouncement else { return }
        let alert = NSAlert()
        alert.alertStyle = announcement.style == "warning" ? .warning : .informational
        alert.messageText = announcement.title
        alert.informativeText = announcement.body
        // With a link, "OK" (dismiss) stays the default action and the link
        // button comes second. Without a link, NSAlert shows its implicit "OK".
        if let link = announcement.link {
            alert.addButton(withTitle: String(localized: "common.button.ok"))
            alert.addButton(withTitle: link.label)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        markPresented(announcement)
        if announcement.link != nil, response == .alertSecondButtonReturn {
            openLink(of: announcement)
        }
    }

    /// Records the announcement as seen and confirms the display to the backend.
    func markPresented(_ announcement: AppBackendClient.Announcement) {
        pendingAnnouncement = nil
        var seenIDs = Preferences.seenBackendAnnouncementIDs
        if !seenIDs.contains(announcement.id) {
            seenIDs.append(announcement.id)
            Preferences.seenBackendAnnouncementIDs = seenIDs
        }
        Task {
            await client.acknowledgeAnnouncement(
                installID: Preferences.appBackendInstallID,
                announcementID: announcement.id
            )
        }
    }

    /// Opens the secondary button's link and counts the click on the backend side.
    func openLink(of announcement: AppBackendClient.Announcement) {
        guard let link = announcement.link, let url = URL(string: link.url) else { return }
        NSWorkspace.shared.open(url)
        Task {
            await client.reportAnnouncementClick(
                installID: Preferences.appBackendInstallID,
                announcementID: announcement.id
            )
        }
    }
}
