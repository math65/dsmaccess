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

    /// Uploading and pasting no longer open a dialog every time: the question is only worth
    /// asking when a name is about to be replaced. Answering "nothing collides" wrongly would
    /// silently overwrite, which is the one outcome this screen must never produce by itself.
    @Test func findsOnlyTheNamesTheDestinationAlreadyHolds() {
        let present = ["rapport.pdf", "photos", "budget.xlsx"]

        #expect(
            FileBrowserViewModel.existingNames(among: ["budget.xlsx", "notes.txt"], in: present)
                == ["budget.xlsx"]
        )
        #expect(
            FileBrowserViewModel.existingNames(among: ["notes.txt"], in: present).isEmpty
        )
        // An empty folder collides with nothing: the case that used to show a form anyway.
        #expect(
            FileBrowserViewModel.existingNames(among: ["rapport.pdf"], in: []).isEmpty
        )
    }

    /// The NAS volumes distinguish case. Treating "Budget.xlsx" as the existing "budget.xlsx"
    /// would announce a conflict that does not exist — and, on "replace", destroy neither of
    /// them while claiming to have replaced one.
    @Test func doesNotConfuseNamesThatDifferOnlyByCase() {
        let existing = FileBrowserViewModel.existingNames(
            among: ["Budget.xlsx", "BUDGET.XLSX"],
            in: ["budget.xlsx"]
        )

        #expect(existing.isEmpty)
    }
}
