//
//  NASSettingsView.swift
//  dsmaccess
//

import SwiftUI

struct NASSettingsView: View {
    let session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusHeading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NAS enregistrés")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            if session.profiles.isEmpty {
                ContentUnavailableView(
                    "Aucun NAS enregistré",
                    systemImage: "externaldrive",
                    description: Text("Ajoutez un NAS depuis cette fenêtre ou depuis le menu NAS.")
                )
            } else {
                List(session.profiles) { profile in
                    NASProfileSettingsRow(
                        profile: profile,
                        isConnected: session.activeProfileID == profile.id,
                        onRename: { session.renameProfile(profile.id, to: $0) },
                        onDelete: { session.removeProfile(profile.id) }
                    )
                }
            }

            HStack {
                Button("Ajouter un NAS…", systemImage: "plus", action: addNAS)
                    .help("Ajouter un NAS à DSM Access")
                Spacer()
            }
        }
        .padding(16)
        .task {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "Réglages des NAS enregistrés"),
                category: .navigation
            )
        }
    }

    private func addNAS() {
        session.prepareNewNAS()
        dismiss()
        Task {
            await session.logout()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
