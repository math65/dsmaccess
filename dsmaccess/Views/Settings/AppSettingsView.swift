//
//  AppSettingsView.swift
//  dsmaccess
//
//  Fenêtre Réglages macOS native.
//

import SwiftUI

struct AppSettingsView: View {
    let settings: AppSettings
    let session: SessionStore

    var body: some View {
        TabView {
            AnnouncementSettingsView(settings: settings)
                .tabItem {
                    Label("Annonces", systemImage: "speaker.wave.2")
                        .help("Configurer les annonces VoiceOver")
                }

            SidebarSettingsView(settings: settings)
                .tabItem {
                    Label("Barre latérale", systemImage: "sidebar.left")
                        .help("Configurer les modules de la barre latérale")
                }

            NASSettingsView(session: session)
                .tabItem {
                    Label("NAS", systemImage: "externaldrive.connected.to.line.below")
                        .help("Gérer les NAS enregistrés")
                }
        }
        .frame(width: 620, height: 520)
    }
}
