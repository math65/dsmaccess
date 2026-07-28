//
//  ControlPanelView.swift
//  dsmaccess
//
//  Point d'entrée des réglages système du NAS.
//

import SwiftUI

struct ControlPanelView: View {
    let session: SessionStore
    @State private var path: [ControlPanelSection] = []
    @AccessibilityFocusState private var focusTitle: Bool
    @AccessibilityFocusState private var focusedSection: ControlPanelSection?

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
                            Button(action: { open(section) }) {
                                HStack(spacing: 8) {
                                    Label(section.title, systemImage: section.systemImage)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .background(.quaternary, in: .rect(cornerRadius: 8))
                            .accessibilityFocused($focusedSection, equals: section)
                            .accessibilityHint(section.hint)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .navigationDestination(for: ControlPanelSection.self) { section in
                switch section {
                case .network:
                    NetworkSettingsView(session: session)
                case .dsmUpdate:
                    DSMUpdateView(session: session)
                }
            }
        }
        .task {
            focusTitle = true
            VoiceOver.announce(
                String(localized: "Panneau de configuration"),
                category: .navigation
            )
        }
        .onChange(of: path) { oldPath, newPath in
            guard !oldPath.isEmpty, newPath.isEmpty, let section = oldPath.last else { return }
            focusedSection = section
        }
    }

    private func open(_ section: ControlPanelSection) {
        path.append(section)
        VoiceOver.announce(section.localizedTitle, category: .navigation)
    }
}
