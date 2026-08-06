import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct OperationFailuresTests {
    @Test func recordingMakesTheFirstFailurePending() {
        let center = OperationFailures()
        center.record(OperationFailure(message: "first", module: .hyperBackup))
        #expect(center.pending?.message == "first")
    }

    @Test func laterFailuresWaitTheirTurn() {
        let center = OperationFailures()
        center.record(OperationFailure(message: "first", module: .hyperBackup))
        center.record(OperationFailure(message: "second", module: .files))
        #expect(center.pending?.message == "first")
        center.dismissPending()
        #expect(center.pending?.message == "second")
        center.dismissPending()
        #expect(center.pending == nil)
    }

    @Test func aMessageAlreadyWaitingIsNotQueuedTwice() {
        let center = OperationFailures()
        center.record(OperationFailure(message: "same", module: .hyperBackup))
        center.record(OperationFailure(message: "same", module: .hyperBackup))
        center.record(OperationFailure(message: "same", module: .hyperBackup))
        center.dismissPending()
        #expect(center.pending == nil)
    }

    @Test func aRepeatedFailureAlertsAgainOnceTheFirstIsClosed() {
        let center = OperationFailures()
        center.record(OperationFailure(message: "same", module: .hyperBackup))
        center.dismissPending()
        center.record(OperationFailure(message: "same", module: .hyperBackup))
        #expect(center.pending?.message == "same")
    }

    @Test func acceptingHandsTheFailureToTheFormOnceOnly() {
        let center = OperationFailures()
        center.record(OperationFailure(message: "boom", module: .hyperBackup))
        center.acceptPending()
        #expect(center.pending == nil)
        #expect(center.consumeAccepted()?.message == "boom")
        #expect(center.consumeAccepted() == nil)
    }

    @Test func dismissingLeavesNothingToConsume() {
        let center = OperationFailures()
        center.record(OperationFailure(message: "boom", module: .hyperBackup))
        center.dismissPending()
        #expect(center.consumeAccepted() == nil)
    }

    @Test func presentingRecordsFailuresAndStaysSilentOnCancellation() {
        let center = OperationFailures()
        center.present(.cancelled, from: .hyperBackup)
        #expect(center.pending == nil)
        center.present(.failure("broken"), from: .hyperBackup)
        #expect(center.pending?.message == "broken")
        #expect(center.pending?.module == .hyperBackup)
    }

    @Test func presentingASuccessDoesNotCreateAnAlert() {
        let center = OperationFailures()
        var refreshed = false
        center.present(.success("done"), from: .hyperBackup) { refreshed = true }
        #expect(center.pending == nil)
        #expect(refreshed)
    }

    @Test func reportPrefillQuotesTheModuleAndTheMessage() {
        let failure = OperationFailure(message: "NAS error (code 4401).", module: .hyperBackup)
        #expect(failure.reportPrefill.contains("NAS error (code 4401)."))
        #expect(failure.reportPrefill.contains(AppModule.hyperBackup.localizedTitle))
    }
}
