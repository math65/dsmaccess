//
//  OperationFailures.swift
//  dsmaccess
//
//  Presents the outcome of a user operation over a channel that cannot be missed: a
//  success is announced, a failure becomes an alert. An announcement is gone the moment
//  it is spoken — missed if attention is elsewhere, lost entirely if the app is in the
//  background — while an alert waits on screen, and VoiceOver reads it on its own.
//

import Foundation

/// A failed user operation, kept until the user closes the alert. `message` is the
/// localized failure text exactly as the operation produced it; `module` names the
/// screen it came from, for the report.
struct OperationFailure: Identifiable, Equatable, Sendable {
    let id = UUID()
    let message: String
    let module: AppModule

    /// Opening text of a report: names the module and quotes the failure, nothing else.
    /// It lands in the contact form's message field, where the user reads and edits it
    /// before anything is sent.
    var reportPrefill: String {
        String(
            localized: "feedback.operation_failure.prefill",
            defaultValue: "An operation failed in \(module.localizedTitle). The app reported: \(message)"
        )
    }
}

/// Collects operation failures and offers one alert at a time: simultaneous failures
/// wait their turn instead of piling up modal alerts, and a failure whose message is
/// already waiting is dropped — with a screen reader, a repeated alert makes the app
/// unusable.
@MainActor
@Observable
final class OperationFailures {
    static let shared = OperationFailures()

    private(set) var pending: OperationFailure?
    private(set) var accepted: OperationFailure?
    private var queue: [OperationFailure] = []

    /// Presents an operation outcome. A success is announced, with the optional hook the
    /// announcement helper already offers. A failure becomes the pending alert and is
    /// deliberately not announced: VoiceOver reads the alert on its own, and an
    /// announcement on top would narrate the same failure twice. A cancellation stays
    /// silent, as everywhere else in the app.
    func present(
        _ outcome: DSMOperationOutcome,
        from module: AppModule,
        onSuccess: () -> Void = { }
    ) {
        switch outcome {
        case .success:
            VoiceOver.announce(outcome, priority: .high, onSuccess: onSuccess)
        case .failure(let message):
            record(OperationFailure(message: message, module: module))
        case .cancelled:
            break
        }
    }

    func record(_ failure: OperationFailure) {
        guard pending != nil else {
            pending = failure
            return
        }
        let alreadyWaiting = pending?.message == failure.message
            || queue.contains { $0.message == failure.message }
        guard !alreadyWaiting else { return }
        queue.append(failure)
    }

    func acceptPending() {
        accepted = pending
        advance()
    }

    func dismissPending() {
        advance()
    }

    /// Hands the accepted failure to the contact form, once only.
    func consumeAccepted() -> OperationFailure? {
        defer { accepted = nil }
        return accepted
    }

    private func advance() {
        pending = queue.isEmpty ? nil : queue.removeFirst()
    }
}
