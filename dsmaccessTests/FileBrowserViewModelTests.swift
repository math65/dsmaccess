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

    private func transfer(
        name: String,
        completed: Int64?,
        total: Int64?,
        state: FileTransferState
    ) -> FileTransferRecord {
        FileTransferRecord(
            direction: .upload,
            name: name,
            source: "/local/\(name)",
            destination: "/photo",
            progress: completed.map { DSMTransferProgress(completedBytes: $0, totalBytes: total) },
            state: state
        )
    }

    /// Sending thirty files is one operation from where the user stands. The banner sums the
    /// batch, and that sum has to be right: it is what feeds the speed and the time remaining.
    @Test func sumsABatchOfTransfersIntoOneProgress() throws {
        let batch = [
            transfer(name: "a.jpg", completed: 1_000, total: 1_000, state: .completed),
            transfer(name: "b.jpg", completed: 500, total: 2_000, state: .running),
            transfer(name: "c.jpg", completed: nil, total: nil, state: .queued),
        ]

        let progress = FileBrowserViewModel.batchProgress(of: batch, identity: "batch-1")

        #expect(progress.processedSize == 1_500)
        #expect(progress.processedItemCount == 1)
        #expect(progress.totalItemCount == 3)
        // The file being sent is what the banner names, not the one already done.
        #expect(progress.currentPath == "b.jpg")
    }

    /// As long as one file has not announced its size, the total is unknown. Guessing one
    /// would show a fraction that jumps backwards when the missing size finally arrives.
    @Test func reportsNoTotalUntilEveryFileHasAnnouncedItsSize() {
        let incomplete = [
            transfer(name: "a.jpg", completed: 1_000, total: 1_000, state: .completed),
            transfer(name: "b.jpg", completed: 0, total: nil, state: .running),
        ]
        let known = [
            transfer(name: "a.jpg", completed: 1_000, total: 1_000, state: .completed),
            transfer(name: "b.jpg", completed: 250, total: 3_000, state: .running),
        ]

        #expect(FileBrowserViewModel.batchProgress(of: incomplete, identity: "b").totalSize == nil)
        #expect(FileBrowserViewModel.batchProgress(of: incomplete, identity: "b").fractionCompleted == nil)
        #expect(FileBrowserViewModel.batchProgress(of: known, identity: "b").totalSize == 4_000)
    }
}
