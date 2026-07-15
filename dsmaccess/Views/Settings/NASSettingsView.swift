//
//  NASSettingsView.swift
//  dsmaccess
//

import SwiftUI

struct NASSettingsView: View {
    let session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .padding(20)
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
