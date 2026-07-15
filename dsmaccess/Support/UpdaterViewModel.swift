//
//  UpdaterViewModel.swift
//  dsmaccess
//
//  Intégration de Sparkle (mises à jour automatiques). On encapsule le contrôleur
//  standard de Sparkle et on expose l'action « Rechercher les mises à jour ».
//
//  Choix : ObservableObject + @Published plutôt que le @Observable du reste du projet.
//  C'est le pattern OFFICIEL de Sparkle pour SwiftUI : le publisher KVO de Sparkle
//  (`canCheckForUpdates`) s'y branche directement, et c'est ce qui rafraîchit de façon
//  fiable l'état activé/désactivé du bouton placé dans un `CommandGroup`.
//

import SwiftUI
import Combine
import Sparkle

/// Abonne le build au canal de mises à jour approprié. Un build **beta** (version contenant
/// « beta », ex. « 1.1-beta.1 ») suit le canal `beta` de l'appcast ; un build **stable** ne
/// suit que le canal par défaut. Le mécanisme est ainsi auto-cohérent : rien à basculer à la
/// main quand on passe d'une beta à une version stable.
final class UpdaterChannelDelegate: NSObject, SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.localizedCaseInsensitiveContains("beta") ? ["beta"] : []
    }
}

final class UpdaterViewModel: ObservableObject {
    private let updaterController: SPUStandardUpdaterController
    /// Retenu fortement : Sparkle ne garde qu'une référence faible au delegate.
    private let channelDelegate = UpdaterChannelDelegate()

    /// Vrai quand Sparkle est prêt à vérifier (évite de proposer l'action trop tôt).
    @Published var canCheckForUpdates = false

    init() {
        // startingUpdater: true → démarre l'updater au lancement et fournit l'UI standard
        // Sparkle (fenêtre « mise à jour disponible », progression, notes de version),
        // qui est en AppKit natif donc accessible VoiceOver sans code supplémentaire.
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                        updaterDelegate: channelDelegate,
                                                        userDriverDelegate: nil)
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Vérification déclenchée manuellement depuis le menu.
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }
}

/// Bouton de menu « Rechercher les mises à jour… ». Isolé dans sa propre vue pour capter
/// la réactivité de l'`ObservableObject` (activation/désactivation selon Sparkle).
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
