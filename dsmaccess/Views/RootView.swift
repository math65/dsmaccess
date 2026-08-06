//
//  RootView.swift
//  dsmaccess
//
//  Shows the sign-in screen or the administration interface depending on the session state.
//

import AppKit
import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.openWindow) private var openWindow
    @State private var announcements = BackendAnnouncementCoordinator()
    @State private var incidents = DSMResponseIncidents.shared
    @State private var failures = OperationFailures.shared

    var body: some View {
        Group {
            if session.isLoggedIn {
                MainView(session: session)
            } else {
                LoginView(session: session)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
        .task {
            await announcements.checkAtLaunch()
            announcements.presentPendingAnnouncement()
        }
        .onChange(of: incidents.pending) { _, incident in
            guard incident != nil else { return }
            presentPendingIncident()
        }
        .onChange(of: failures.pending) { _, failure in
            guard failure != nil else { return }
            presentPendingFailure()
        }
    }

    /// Same NSAlert choice as the incident alert below. The app is deliberately not
    /// activated: when the failure lands while the user is working elsewhere, the
    /// operation's own completion signal already reaches them, and pulling the whole app
    /// forward would steal their focus mid-keystroke — the alert simply waits for their
    /// return.
    private func presentPendingFailure() {
        guard let failure = failures.pending else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "root.operation_failure.title")
        alert.informativeText = failure.message
        alert.addButton(withTitle: String(localized: "common.button.ok"))
        alert.addButton(withTitle: String(localized: "root.operation_failure.report.button"))

        if alert.runModal() == .alertSecondButtonReturn {
            failures.acceptPending()
            openWindow(id: "feedback")
        } else {
            failures.dismissPending()
        }
    }

    /// NSAlert and not SwiftUI's `.alert` modifier, for the same reason as the backend
    /// announcements: permanently attached to the root, that modifier makes the window's
    /// accessibility audit fail.
    private func presentPendingIncident() {
        guard let incident = incidents.pending else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "root.decoding_failure.title")
        alert.informativeText = String(
            localized: "root.decoding_failure.message", defaultValue: "The operation failed: DSM Access could not read what \(incident.api) replied. Reporting sends the call involved and the names of the fields received, never their contents."
        )
        alert.addButton(withTitle: String(localized: "root.decoding_failure.report.button"))
        alert.addButton(withTitle: String(localized: "root.decoding_failure.dismiss.button"))
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            incidents.acceptPending()
            openWindow(id: "feedback")
        } else {
            incidents.ignorePending()
        }
    }
}
