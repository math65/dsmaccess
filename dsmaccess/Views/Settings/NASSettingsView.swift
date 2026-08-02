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
                    "nas.settings.empty.title",
                    systemImage: "externaldrive",
                    description: Text("nas.settings.empty.description")
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
                .accessibilityLabel("nas.settings.profiles.label")
            }

            HStack {
                Button("common.action.add_nas", systemImage: "plus", action: addNAS)
                    .help("common.action.add_nas.hint")
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
