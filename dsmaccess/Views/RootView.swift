//
//  RootView.swift
//  dsmaccess
//
//  Affiche la connexion ou l'interface d'administration selon l'état de la session.
//

import AppKit
import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.openWindow) private var openWindow
    @State private var announcements = BackendAnnouncementCoordinator()
    @State private var incidents = DSMResponseIncidents.shared

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
    }

    /// NSAlert et non le modificateur `.alert` de SwiftUI, pour la même raison que les
    /// annonces du backend : attaché en permanence à la racine, celui-ci fait échouer
    /// l'audit d'accessibilité de la fenêtre.
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
