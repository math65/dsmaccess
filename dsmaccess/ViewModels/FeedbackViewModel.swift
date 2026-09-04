//
//  FeedbackViewModel.swift
//  dsmaccess
//
//  Orchestration of the "Contact the developer" form: light validation, choice of route
//  (report with diagnostics for a problem, plain contact otherwise), protection against
//  double submission and VoiceOver announcements.
//

import Foundation

@Observable
final class FeedbackViewModel {
    var contactType: AppBackendClient.ContactType = .bug
    var email = Preferences.feedbackEmail
    var message = ""
    /// Unreadable reply the user chose to report: attached to the report, and shown again on
    /// screen so they know what they are sending before confirming.
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

    /// Minimal client-side validation (an "@" with text on both sides): the real validation
    /// belongs to the server.
    var emailLooksPlausible: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty } && parts[1].contains(".")
    }

    var canSend: Bool {
        !isSending && emailLooksPlausible && !trimmedMessage.isEmpty
    }

    /// Picks up the incident accepted in the alert and prepares a report to fill in. The
    /// starting message stays editable: the user describes what they were doing, the
    /// technical part is attached separately.
    func adoptPendingIncident() {
        guard incident == nil, let accepted = DSMResponseIncidents.shared.consumeAccepted() else {
            return
        }
        incident = accepted
        contactType = .bug
        if trimmedMessage.isEmpty {
            message = String(localized: "feedback.unreadable_reply.title")
        }
    }

    /// Picks up the operation failure the user chose to report from the alert. The failure
    /// is quoted at the top of the message, where it stays visible and editable: what gets
    /// sent is exactly what the field shows.
    func adoptPendingOperationFailure() {
        guard let failure = OperationFailures.shared.consumeAccepted() else { return }
        contactType = .bug
        if trimmedMessage.isEmpty {
            message = failure.reportPrefill
        } else {
            message += "\n\n" + failure.reportPrefill
        }
    }

    func send(session: SessionStore, settings: AppSettings) async {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        VoiceOver.announce(String(localized: "common.status.sending_message"), category: .progress)
        do {
            if contactType == .bug {
                let sections = FeedbackDiagnostics.sections(
                    sessionConnected: session.isLoggedIn,
                    nasModel: session.nasModel,
                    dsmVersion: session.dsmVersion,
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
            VoiceOver.announce(String(localized: "feedback.send.done.announcement"), category: .result)
        } catch {
            let message = (error as? AppBackendClient.BackendError)?.localizedMessage
                ?? AppBackendClient.BackendError.server.localizedMessage
            errorMessage = message
            VoiceOver.announce(message, category: .error, priority: .high)
        }
    }
}
