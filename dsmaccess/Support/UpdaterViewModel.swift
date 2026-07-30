//
//  UpdaterViewModel.swift
//  dsmaccess
//
//  Sparkle integration for automatic and manual updates.
//

import SwiftUI
import Combine
import Sparkle

/// Subscribes prereleases to the beta channel and stable versions to the default channel.
final class UpdaterChannelDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.localizedCaseInsensitiveContains("beta") ? ["beta"] : []
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
