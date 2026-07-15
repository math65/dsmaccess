//
//  SidebarSettingsView.swift
//  dsmaccess
//

import SwiftUI

struct SidebarSettingsView: View {
    @Bindable var settings: AppSettings
    @State private var selection: AppModule?
    @AccessibilityFocusState private var focusHeading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Barre latérale")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            Text("Cochez les modules à afficher. Faites-les glisser pour les réordonner dans leur section, ou sélectionnez-en un puis utilisez Commande + Flèche vers le haut ou Commande + Flèche vers le bas.")
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(AppModuleSection.allCases) { section in
                    Section(section.title) {
                        ForEach(modules(in: section)) { module in
                            Toggle(isOn: enabledBinding(for: module)) {
                                Label(module.title, systemImage: module.systemImage)
                            }
                            .tag(module)
                            .help(String(localized: "Afficher ou masquer \(module.localizedTitle) dans la barre latérale"))
                            .draggable(module.rawValue)
                            .dropDestination(for: String.self) { values, _ in
                                move(values.first, before: module)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Monter", systemImage: "arrow.up", action: moveSelectionUp)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!canMoveSelection(by: -1))
                    .help("Déplacer le module sélectionné vers le haut")
                Button("Descendre", systemImage: "arrow.down", action: moveSelectionDown)
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .disabled(!canMoveSelection(by: 1))
                    .help("Déplacer le module sélectionné vers le bas")
                Spacer()
            }

            Toggle(
                "Masquer automatiquement les fonctionnalités indisponibles sur le NAS connecté",
                isOn: $settings.automaticallyHideUnavailableModules
            )
            .help("Masquer les modules qui ne sont pas disponibles sur le NAS connecté")
        }
        .padding(16)
        .task {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "Réglages de la barre latérale"),
                category: .navigation
            )
        }
    }

    private func modules(in section: AppModuleSection) -> [AppModule] {
        settings.sidebarOrder.filter { $0.section == section }
    }

    private func enabledBinding(for module: AppModule) -> Binding<Bool> {
        Binding(
            get: { settings.enabledSidebarModules.contains(module) },
            set: { isEnabled in
                selection = module
                if isEnabled {
                    settings.enabledSidebarModules.insert(module)
                } else {
                    settings.enabledSidebarModules.remove(module)
                }
            }
        )
    }

    private func move(_ rawValue: String?, before destination: AppModule) -> Bool {
        guard let rawValue, let source = AppModule(rawValue: rawValue),
              source.section == destination.section else { return false }
        settings.moveSidebarModule(source, before: destination)
        selection = source
        announceMove(source)
        return true
    }

    private func moveSelectionUp() {
        moveSelection(by: -1)
    }

    private func moveSelectionDown() {
        moveSelection(by: 1)
    }

    private func moveSelection(by offset: Int) {
        guard let selection, settings.moveSidebarModule(selection, by: offset) else { return }
        announceMove(selection)
    }

    private func canMoveSelection(by offset: Int) -> Bool {
        guard let selection else { return false }
        let modules = modules(in: selection.section)
        guard let index = modules.firstIndex(of: selection) else { return false }
        return modules.indices.contains(index + offset)
    }

    private func announceMove(_ module: AppModule) {
        let modules = modules(in: module.section)
        guard let index = modules.firstIndex(of: module) else { return }
        VoiceOver.announce(
            String(localized: "\(module.localizedTitle), position \(index + 1) sur \(modules.count)"),
            category: .result
        )
    }
}
