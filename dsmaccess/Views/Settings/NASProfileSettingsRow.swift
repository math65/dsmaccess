//
//  NASProfileSettingsRow.swift
//  dsmaccess
//

import SwiftUI

struct NASProfileSettingsRow: View {
    let profile: NASProfile
    let isConnected: Bool
    let onRename: (String) -> Void
    let onDelete: () -> Void

    @State private var name: String

    init(
        profile: NASProfile,
        isConnected: Bool,
        onRename: @escaping (String) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.profile = profile
        self.isConnected = isConnected
        self.onRename = onRename
        self.onDelete = onDelete
        _name = State(initialValue: profile.displayName)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Nom du NAS", text: $name)
                    .onSubmit(rename)
                    .accessibilityLabel("Nom du NAS")
                    .help("Modifier le nom affiché pour ce NAS")
                Text("\(profile.account) — \(profile.host):\(profile.port)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if isConnected {
                Text("Connecté")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("NAS connecté")
            }

            Button("Renommer", action: rename)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Enregistrer le nouveau nom du NAS")

            Button("Supprimer", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .disabled(isConnected)
                .help(isConnected ? "Déconnectez-vous avant de supprimer ce NAS" : "Supprimer ce NAS")
        }
    }

    private func rename() {
        onRename(name)
        VoiceOver.announce(
            String(localized: "NAS renommé \(name)"),
            category: .result
        )
    }
}
