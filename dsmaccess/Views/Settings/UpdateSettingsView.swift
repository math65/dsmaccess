//
//  UpdateSettingsView.swift
//  dsmaccess
//
//  Settings for the app's updates (Sparkle).
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
                    .foregroundStyle(.readableSecondary)
            }

            Section("updates.settings.beta.section") {
                Toggle("updates.settings.beta", isOn: $updater.receivesBetaUpdates)
                    .help("updates.settings.beta.description")
                // Turning this off on a beta build does not go back to the stable version:
                // saying so here spares the impression that updates have stopped working.
                Text(
                    updater.receivesBetaUpdates
                        ? "updates.settings.beta.on.description"
                        : Preferences.isRunningBeta
                            ? "updates.settings.beta.off_on_beta.description"
                            : "updates.settings.beta.off.description"
                )
                .font(.callout)
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
