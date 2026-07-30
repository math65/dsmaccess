//
//  dsmaccessApp.swift
//  dsmaccess
//
//  Created by Mathieu Martin on 09/07/2026.
//

import AppKit
import SwiftUI

@main
struct dsmaccessApp: App {
    /// Session state shared across the whole app (current SID, host, connected or not).
    @State private var session = SessionStore()
    @State private var settings = AppSettings()
    /// Sparkle updater, owned by the app for its whole lifetime.
    @StateObject private var updater = UpdaterViewModel()

    init() {
        // The unit tests are hosted by the app, but they do not test its windows. Preventing
        // activation keeps them from interrupting the user on every run.
        let environment = ProcessInfo.processInfo.environment
        if environment["DSM_ACCESS_BACKGROUND_TESTS"] == "YES"
            || environment["XCTestConfigurationFilePath"] != nil {
            NSApplication.shared.setActivationPolicy(.prohibited)
        }
    }

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

        Window("common.action.contact_developer", id: "feedback") {
            FeedbackView()
                .environment(session)
                .environment(settings)
        }
        .windowResizability(.contentSize)

        Settings {
            AppSettingsView(settings: settings, session: session, updater: updater)
                .environment(settings)
                .environment(session)
        }
        .defaultSize(width: 820, height: 600)
        .windowResizability(.contentMinSize)
    }
}
