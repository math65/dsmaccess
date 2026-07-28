import Testing
@testable import dsmaccess

@MainActor
struct FileBrowserViewModelTests {
    @Test func distinguishesLostTrackingFromAFailedOperation() {
        let vm = FileBrowserViewModel(session: SessionStore())

        let interrupted = vm.operationSummary(
            for: FileOperationTrackingInterrupted(
                kind: .copyMove,
                taskID: "copy-1",
                underlying: DSMError.network("délai dépassé")
            )
        )
        let failed = vm.operationSummary(for: DSMError.permissionDenied)

        #expect(interrupted.continuesInBackground)
        #expect(!failed.continuesInBackground)
        #expect(interrupted.message != failed.message)
    }
}
