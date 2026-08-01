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
                TextField("common.field.nas_name", text: $name)
                    .onSubmit(rename)
                    .accessibilityLabel("common.field.nas_name")
                    .help("nas.profile.rename.hint")
                connectionDescription
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
            }

            if isConnected {
                Text("common.status.connected")
                    .foregroundStyle(.readableSecondary)
                    .accessibilityLabel("nas.profile.connected")
            }

            Button("common.button.rename", action: rename)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("common.button.save_nas_name")

            Button("common.button.delete", systemImage: "trash", role: .destructive, action: onDelete)
                .labelStyle(.iconOnly)
                .disabled(isConnected)
                .help(isConnected ? "nas.profile.delete.disabled.hint" : "nas.profile.delete.button")
        }
    }

    private func rename() {
        onRename(name)
        VoiceOver.announce(
            String(localized: "common.status.nas_renamed", defaultValue: "NAS renamed \(name)"),
            category: .result
        )
    }

    @ViewBuilder
    private var connectionDescription: some View {
        switch profile.connection {
        case .direct(let endpoint):
            Text(String(localized: "nas.profile.address.host_port", defaultValue: "\(profile.account) — \(endpoint.host):\(endpoint.port)"))
        case .quickConnect(let id):
            Text(String(localized: "nas.profile.address.quickconnect", defaultValue: "\(profile.account) — QuickConnect \(id)"))
        }
    }
}
