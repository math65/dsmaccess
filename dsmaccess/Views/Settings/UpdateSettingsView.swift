//
//  UpdateSettingsView.swift
//  dsmaccess
//
//  Réglages des mises à jour de l'app (Sparkle).
//

import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Form {
            Section("updates.settings.section.title") {
                Toggle(
                    "updates.settings.auto_check",
                    isOn: $updater.automaticallyChecksForUpdates
                )
                .help("updates.settings.auto_check.description")
                Toggle(
                    "updates.settings.auto_install",
                    isOn: $updater.automaticallyDownloadsUpdates
                )
                .disabled(!updater.automaticallyChecksForUpdates)
                .help("updates.settings.auto_install.description")
                Text("updates.settings.section.footer")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("common.label.installed_version", value: Self.installedVersion)
                Button("updates.settings.check_now.button") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                .help("common.action.check_for_app_update")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private static var installedVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "updates.settings.version.value", defaultValue: "\(version) (build \(build))")
    }
}
