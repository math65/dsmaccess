//
//  ControlPanelView.swift
//  dsmaccess
//
//  Entry point for the NAS system settings.
//

import SwiftUI

struct ControlPanelView: View {
    let session: SessionStore
    let externalDevices: ExternalDevicesViewModel
    /// Section the toolbar menu asked for, so "External device settings" lands on the screen
    /// itself rather than on the Control Panel index.
    @Binding var requestedSection: ControlPanelSection?
    @State private var path: [ControlPanelSection] = []
    @AccessibilityFocusState private var focusTitle: Bool
    @AccessibilityFocusState private var focusedSection: ControlPanelSection?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("common.module.control_panel")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusTitle)
                    Text("control_panel.description")
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)
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
            .accessibilityLabel("control_panel.sections.label")
            .navigationDestination(for: ControlPanelSection.self) { section in
                switch section {
                case .network:
                    NetworkSettingsView(session: session)
                case .externalDevices:
                    ExternalDevicesView(model: externalDevices)
                case .dsmUpdate:
                    DSMUpdateView(session: session)
                }
            }
        }
        .task {
            focusTitle = true
            VoiceOver.announce(
                String(localized: "common.module.control_panel"),
                category: .navigation
            )
        }
        .onChange(of: path) { oldPath, newPath in
            guard !oldPath.isEmpty, newPath.isEmpty, let section = oldPath.last else { return }
            focusedSection = section
        }
        .task(id: requestedSection) {
            guard let section = requestedSection else { return }
            requestedSection = nil
            guard path.last != section else { return }
            open(section)
        }
    }

    private func open(_ section: ControlPanelSection) {
        path.append(section)
        VoiceOver.announce(section.localizedTitle, category: .navigation)
    }
}
