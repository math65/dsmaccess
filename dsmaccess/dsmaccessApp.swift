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
    /// Updater Sparkle, propriété de l'app pour toute sa durée de vie.
    @StateObject private var updater = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .frame(minWidth: 800, idealWidth: 960, minHeight: 520, idealHeight: 640)
        }
        .defaultSize(width: 1_100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            DSMCommands()
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater)
            }
        }
    }
}
