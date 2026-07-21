//
//  BackendAnnouncementCoordinator.swift
//  dsmaccess
//
//  Vérifie au lancement si le backend a un message de l'éditeur à afficher, et
//  applique côté client le mode « une seule fois » (le serveur renvoie toujours
//  l'annonce active). L'échec du réseau est silencieux : ce service est
//  facultatif et ne doit jamais gêner le démarrage.
//
//  La présentation passe par NSAlert et non par le modificateur `.alert` de
//  SwiftUI : attaché en permanence à la racine, celui-ci fait échouer l'audit
//  d'accessibilité de la fenêtre (hiérarchie parent/enfant incohérente), alors
//  que NSAlert est entièrement lu par VoiceOver et gère le clavier nativement.
//

import AppKit

final class BackendAnnouncementCoordinator {
    /// Annonce retenue par `checkAtLaunch`, à présenter via `presentPendingAnnouncement`.
    /// Séparée de la présentation pour rester testable sans interface.
    private(set) var pendingAnnouncement: AppBackendClient.Announcement?

    private let client: AppBackendClient
    private var didCheck = false

    init(client: AppBackendClient = AppBackendClient()) {
        self.client = client
    }

    func checkAtLaunch() async {
        guard !didCheck else { return }
        didCheck = true
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true ? "fr" : "en"
        guard let announcement = try? await client.checkAnnouncement(
            installID: Preferences.appBackendInstallID,
            language: language
        ) else {
            return
        }
        if announcement.mode == "once", Preferences.seenBackendAnnouncementIDs.contains(announcement.id) {
            return
        }
        pendingAnnouncement = announcement
    }

    /// Affiche l'annonce en attente dans une alerte modale, puis confirme
    /// l'affichage au backend et compte l'activation éventuelle du bouton lien.
    func presentPendingAnnouncement() {
        guard let announcement = pendingAnnouncement else { return }
        let alert = NSAlert()
        alert.alertStyle = announcement.style == "warning" ? .warning : .informational
        alert.messageText = announcement.title
        alert.informativeText = announcement.body
        // Avec un lien, « OK » (fermer) reste l'action par défaut et le bouton
        // lien vient en second. Sans lien, NSAlert affiche son « OK » implicite.
        if let link = announcement.link {
            alert.addButton(withTitle: String(localized: "OK"))
            alert.addButton(withTitle: link.label)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        markPresented(announcement)
        if announcement.link != nil, response == .alertSecondButtonReturn {
            openLink(of: announcement)
        }
    }

    /// Mémorise l'annonce comme vue et confirme l'affichage au backend.
    func markPresented(_ announcement: AppBackendClient.Announcement) {
        pendingAnnouncement = nil
        var seenIDs = Preferences.seenBackendAnnouncementIDs
        if !seenIDs.contains(announcement.id) {
            seenIDs.append(announcement.id)
            Preferences.seenBackendAnnouncementIDs = seenIDs
        }
        Task {
            await client.acknowledgeAnnouncement(
                installID: Preferences.appBackendInstallID,
                announcementID: announcement.id
            )
        }
    }

    /// Ouvre le lien du bouton secondaire et compte le clic côté backend.
    func openLink(of announcement: AppBackendClient.Announcement) {
        guard let link = announcement.link, let url = URL(string: link.url) else { return }
        NSWorkspace.shared.open(url)
        Task {
            await client.reportAnnouncementClick(
                installID: Preferences.appBackendInstallID,
                announcementID: announcement.id
            )
        }
    }
}
