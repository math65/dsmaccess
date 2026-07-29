//
//  FeedbackViewModel.swift
//  dsmaccess
//
//  Orchestration du formulaire « Contacter le développeur » : validation légère,
//  choix de la route (rapport avec diagnostic pour un problème, contact simple
//  sinon), protection contre le double envoi et annonces VoiceOver.
//

import Foundation

@Observable
final class FeedbackViewModel {
    var contactType: AppBackendClient.ContactType = .bug
    var email = Preferences.feedbackEmail
    var message = ""
    /// Réponse illisible que l'utilisateur a choisi de signaler : jointe au rapport,
    /// et rappelée à l'écran pour qu'il sache ce qu'il envoie avant de valider.
    private(set) var incident: DSMResponseIncident?
    private(set) var isSending = false
    private(set) var errorMessage: String?
    private(set) var didSucceed = false

    private let client: AppBackendClient

    init(client: AppBackendClient = AppBackendClient()) {
        self.client = client
    }

    var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validation minimale côté client (présence d'un « @ » entouré de texte) :
    /// la validation réelle appartient au serveur.
    var emailLooksPlausible: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty } && parts[1].contains(".")
    }

    var canSend: Bool {
        !isSending && emailLooksPlausible && !trimmedMessage.isEmpty
    }

    /// Reprend l'incident accepté dans l'alerte et prépare un rapport à compléter.
    /// Le message de départ reste modifiable : c'est l'utilisateur qui décrit ce
    /// qu'il faisait, la partie technique est jointe séparément.
    func adoptPendingIncident() {
        guard incident == nil, let accepted = DSMResponseIncidents.shared.consumeAccepted() else {
            return
        }
        incident = accepted
        contactType = .bug
        if trimmedMessage.isEmpty {
            message = String(localized: "DSM Access n’a pas su lire une réponse du NAS.")
        }
    }

    func send(sessionConnected: Bool, settings: AppSettings) async {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        VoiceOver.announce(String(localized: "Envoi du message en cours"), category: .progress)
        do {
            if contactType == .bug {
                let sections = FeedbackDiagnostics.sections(
                    sessionConnected: sessionConnected,
                    profileCount: Preferences.nasProfiles.count,
                    settings: settings,
                    incident: incident
                )
                try await client.sendReport(
                    email: trimmedEmail,
                    summary: trimmedMessage,
                    subjectHint: "Signalement depuis l'app (v\(AppBackendClient.appVersion))",
                    sections: sections
                )
            } else {
                try await client.sendContact(email: trimmedEmail, type: contactType, message: trimmedMessage)
            }
            Preferences.feedbackEmail = trimmedEmail
            didSucceed = true
            VoiceOver.announce(String(localized: "Message envoyé. Merci !"), category: .result)
        } catch {
            let message = (error as? AppBackendClient.BackendError)?.localizedMessage
                ?? AppBackendClient.BackendError.server.localizedMessage
            errorMessage = message
            VoiceOver.announce(message, category: .error, priority: .high)
        }
    }
}
