//
//  AnnouncementSettingsView.swift
//  dsmaccess
//

import SwiftUI

struct AnnouncementSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("Comportement") {
                Toggle(
                    "Mettre les annonces en file d’attente",
                    isOn: $settings.queueAnnouncements
                )
                .help("Lit toutes les annonces dans l’ordre sans interrompre l’annonce précédente")
                Text("Lorsque cette option est activée, les annonces rapides comme « chargement » puis « terminé » sont toutes lues dans l’ordre.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(AnnouncementCategory.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title)
                            Text(category.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(category.title)
                    .accessibilityHint(category.detail)
                    .help(category.detail)
                }
            } header: {
                Text("Annonces VoiceOver")
            } footer: {
                Text("Ces réglages affectent les annonces supplémentaires de DSM Access. Les libellés et états standards des contrôles restent toujours disponibles à VoiceOver.")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func binding(for category: AnnouncementCategory) -> Binding<Bool> {
        Binding(
            get: { settings.enabledAnnouncementCategories.contains(category) },
            set: { isEnabled in
                if isEnabled {
                    settings.enabledAnnouncementCategories.insert(category)
                } else {
                    settings.enabledAnnouncementCategories.remove(category)
                }
            }
        )
    }
}
