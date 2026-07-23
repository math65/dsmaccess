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
        // La vérification automatique est active d'office via SUEnableAutomaticChecks
        // dans l'Info.plist : la doc Sparkle réserve les API runtime aux changements
        // décidés par l'utilisateur (panneau Réglages > Mises à jour) et proscrit
        // leur usage pour poser le comportement par défaut.
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        // Le planificateur interne de Sparkle vérifie au plus une fois par 24 h,
        // ce qui laisse un testeur beta une version en retard quand deux builds
        // sortent le même jour. Cette vérification explicite à chaque lancement
        // est silencieuse (aucune UI sans nouvelle version) et suit le réglage
        // du panneau Réglages > Mises à jour.
        if updaterController.updater.automaticallyChecksForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    /// Vérification périodique (au lancement puis environ une fois par jour).
    /// Sparkle persiste lui-même ce choix dans les préférences.
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Téléchargement silencieux : la mise à jour s'installe à la fermeture de
    /// l'app au lieu de proposer un dialogue à chaque nouvelle version.
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
