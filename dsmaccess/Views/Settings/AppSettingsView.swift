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
    @ObservedObject var updater: UpdaterViewModel
    @AppStorage("selectedSettingsPane") private var selection = AppSettingsPane.announcements

    var body: some View {
        TabView(selection: $selection) {
            AnnouncementSettingsView(settings: settings)
                .tabItem {
                    Label(
                        AppSettingsPane.announcements.title,
                        systemImage: AppSettingsPane.announcements.systemImage
                    )
                }
                .tag(AppSettingsPane.announcements)

            SidebarSettingsView(settings: settings)
                .tabItem {
                    Label(
                        AppSettingsPane.sidebar.title,
                        systemImage: AppSettingsPane.sidebar.systemImage
                    )
                }
                .tag(AppSettingsPane.sidebar)

            NASSettingsView(session: session)
                .tabItem {
                    Label(
                        AppSettingsPane.nas.title,
                        systemImage: AppSettingsPane.nas.systemImage
                    )
                }
                .tag(AppSettingsPane.nas)

            UpdateSettingsView(updater: updater)
                .tabItem {
                    Label(
                        AppSettingsPane.updates.title,
                        systemImage: AppSettingsPane.updates.systemImage
                    )
                }
                .tag(AppSettingsPane.updates)
        }
        .background(SettingsWindowConfigurator())
        .accessibilityIdentifier("settings.panes")
        .frame(minWidth: 640, idealWidth: 720, minHeight: 440, idealHeight: 520)
        .task {
            announceSelection(selection)
        }
        .onChange(of: selection) { _, newValue in
            announceSelection(newValue)
        }
    }

    private func announceSelection(_ pane: AppSettingsPane) {
        VoiceOver.announce(
            String(localized: "Réglages, \(pane.localizedTitle)"),
            category: .navigation
        )
    }
}
