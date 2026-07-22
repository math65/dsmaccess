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
            Section("Mises à jour automatiques") {
                Toggle(
                    "Rechercher automatiquement les mises à jour",
                    isOn: $updater.automaticallyChecksForUpdates
                )
                .help("Vérifie au lancement, puis environ une fois par jour")
                Toggle(
                    "Télécharger et installer automatiquement",
                    isOn: $updater.automaticallyDownloadsUpdates
                )
                .disabled(!updater.automaticallyChecksForUpdates)
                .help("Installe la mise à jour à la fermeture de l’app, sans rien demander")
                Text("Avec le téléchargement automatique, la nouvelle version s’installe à la fermeture de l’app : plus de dialogue à chaque mise à jour.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version installée", value: Self.installedVersion)
                Button("Rechercher maintenant…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                .help("Rechercher une nouvelle version de DSM Access")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private static var installedVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "\(version) (build \(build))")
    }
}
