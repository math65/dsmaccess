//
//  UpdaterViewModel.swift
//  dsmaccess
//
//  Intégration de Sparkle pour les mises à jour automatiques et manuelles.
//

import SwiftUI
import Combine
import Sparkle

/// Abonne les préversions au canal beta et les versions stables au canal par défaut.
final class UpdaterChannelDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.localizedCaseInsensitiveContains("beta") ? ["beta"] : []
    }
}

/// `ObservableObject` permet de relayer directement l'état KVO publié par Sparkle.
final class UpdaterViewModel: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    /// Retenu fortement : Sparkle ne garde qu'une référence faible au delegate.
    private let channelDelegate = UpdaterChannelDelegate()

    /// Indique si Sparkle est prêt à lancer une vérification.
    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                        updaterDelegate: channelDelegate,
                                                        userDriverDelegate: nil)
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

/// Bouton de menu qui suit la disponibilité publiée par Sparkle.
struct CheckForUpdatesView: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Button("Rechercher les mises à jour…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
        .help("Rechercher une nouvelle version de DSM Access")
    }
}
