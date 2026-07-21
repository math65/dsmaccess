//
//  dsmaccessApp.swift
//  dsmaccess
//
//  Created by Mathieu Martin on 09/07/2026.
//

import SwiftUI

@main
struct dsmaccessApp: App {
    /// État de session partagé pour toute l'app (SID courant, hôte, connecté ou non).
    @State private var session = SessionStore()
    @State private var settings = AppSettings()
    /// Updater Sparkle, propriété de l'app pour toute sa durée de vie.
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(settings)
                .frame(minWidth: 800, idealWidth: 960, minHeight: 520, idealHeight: 640)
        }
        .defaultSize(width: 1_100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            DSMCommands()
            FeedbackCommands()
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater)
            }
        }

        Window("Contacter le développeur", id: "feedback") {
            FeedbackView()
                .environment(session)
                .environment(settings)
        }
        .windowResizability(.contentSize)

        Settings {
            AppSettingsView(settings: settings, session: session)
                .environment(settings)
                .environment(session)
        }
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)
    }
}
