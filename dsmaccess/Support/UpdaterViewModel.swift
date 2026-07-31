//
//  UpdaterViewModel.swift
//  dsmaccess
//
//  Sparkle integration for automatic and manual updates.
//

import SwiftUI
import Combine
import Sparkle

/// Opens the beta channel when the user asks for it. Sparkle calls this on every check, so
/// the setting takes effect from the next one without restarting anything.
final class UpdaterChannelDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Preferences.receivesBetaUpdates ? ["beta"] : []
    }
}

/// `ObservableObject` lets us relay the KVO state published by Sparkle directly.
final class UpdaterViewModel: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    /// Held strongly: Sparkle only keeps a weak reference to the delegate.
    private let channelDelegate = UpdaterChannelDelegate()

    /// Whether Sparkle is ready to start a check.
    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                        updaterDelegate: channelDelegate,
                                                        userDriverDelegate: nil)
        // Automatic checking is on by default through SUEnableAutomaticChecks in the
        // Info.plist: the Sparkle docs reserve the runtime APIs for changes the user
        // decides on (Settings > Updates pane) and forbid using them to set the
        // default behaviour.
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        // Sparkle's internal scheduler checks at most once every 24 h, which leaves
        // a beta tester one version behind when two builds ship on the same day.
        // This explicit check on every launch is silent (no UI unless there is a
        // new version) and follows the setting in the Settings > Updates pane.
        if updaterController.updater.automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    /// Periodic check (at launch, then roughly once a day).
    /// Sparkle persists this choice in the preferences itself.
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Silent download: the update installs when the app quits instead of
    /// offering a dialog for every new version.
    var automaticallyDownloadsUpdates: Bool {
        get { updaterController.updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updaterController.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// Whether the beta channel is included in the checks. Turning it on looks for a beta right
    /// away, silently: waiting up to a day for the scheduler would look like the setting had
    /// done nothing. Turning it off changes nothing to the installed version — the app stays on
    /// the beta it is running until a stable release overtakes it.
    var receivesBetaUpdates: Bool {
        get { Preferences.receivesBetaUpdates }
        set {
            objectWillChange.send()
            Preferences.receivesBetaUpdates = newValue
            if newValue { updaterController.updater.checkForUpdatesInBackground() }
        }
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

/// Menu button that follows the availability published by Sparkle.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Button("updates.menu.check.button") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
        .help("common.action.check_for_app_update")
    }
}
