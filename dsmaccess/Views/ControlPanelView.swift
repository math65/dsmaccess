//
//  ControlPanelView.swift
//  dsmaccess
//
//  Hub « Panneau de configuration » : liste de sous-sections (Réseau, et plus tard Heure,
//  Matériel, Sécurité…) navigables via un NavigationStack. Étendre = 1 cas à
//  `ControlPanelSection` + 1 branche du switch de destination.
//
//  Les sous-sections sont des BOUTONS (pas une List + NavigationLink) : sinon, sous VoiceOver,
//  le simple déplacement du curseur change la sélection et OUVRE la sous-vue. Un bouton ne
//  s'active qu'à l'activation explicite (VO-Espace, Entrée, clic). Même raison que le passage
//  du navigateur de fichiers à NSTableView.
//

import SwiftUI

/// Sous-sections du Panneau de configuration.
enum ControlPanelSection: Hashable, CaseIterable, Identifiable {
    case network

    var id: Self { self }

    var label: LocalizedStringKey {
        switch self {
        case .network: return "Réseau et identité"
        }
    }

    var systemImage: String {
        switch self {
        case .network: return "network"
        }
    }

    var hint: LocalizedStringKey {
        switch self {
        case .network: return "Nom du serveur, adresse IP, passerelle, DNS"
        }
    }
}

struct ControlPanelView: View {
    let session: SessionStore
    @State private var path: [ControlPanelSection] = []
    @AccessibilityFocusState private var focusTitle: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Panneau de configuration")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusTitle)
                    Text("Réglages système du NAS, regroupés par domaine.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 8) {
                        ForEach(ControlPanelSection.allCases) { section in
                            Button {
                                path.append(section)
                            } label: {
                                sectionRow(section)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(section.hint)
                        }
                    }
                }
                .padding(28)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .navigationDestination(for: ControlPanelSection.self) { section in
                switch section {
                case .network:
                    NetworkSettingsView(session: session)
                }
            }
        }
        .task {
            focusTitle = true
            VoiceOver.announce(String(localized: "Panneau de configuration"))
        }
    }

    private func sectionRow(_ section: ControlPanelSection) -> some View {
        HStack(spacing: 10) {
            Label(section.label, systemImage: section.systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}
