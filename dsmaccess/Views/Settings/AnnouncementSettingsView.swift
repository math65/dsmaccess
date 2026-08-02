//
//  AnnouncementSettingsView.swift
//  dsmaccess
//

import SwiftUI

struct AnnouncementSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section("announcements.settings.behavior.section") {
                Toggle(
                    "announcements.settings.queue",
                    isOn: $settings.queueAnnouncements
                )
                .help("announcements.settings.queue.description")
                Text("announcements.settings.queue.footer")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)

                Toggle(
                    "announcements.settings.notify_long_operation",
                    isOn: $settings.notifiesFinishedOperations
                )
                .help("announcements.settings.notify_long_operation.description")
                Text("announcements.settings.notify_long_operation.footer")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)

                Toggle(
                    "announcements.settings.sound",
                    isOn: $settings.playsCompletionSound
                )
                .help("announcements.settings.sound.description")
                Text("announcements.settings.sound.footer")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
            }

            Section {
                ForEach(AnnouncementCategory.allCases) { category in
                    Toggle(isOn: binding(for: category)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title)
                            Text(category.detail)
                                .font(.callout)
                                .foregroundStyle(.readableSecondary)
                        }
                    }
                    .accessibilityLabel(category.title)
                    .accessibilityHint(category.detail)
                    .help(category.detail)
                }
            } header: {
                Text("announcements.settings.title")
            } footer: {
                Text("announcements.settings.categories.footer")
            }
        }
        .formStyle(.grouped)
        .accessibilityLabel("announcements.settings.form.label")
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
