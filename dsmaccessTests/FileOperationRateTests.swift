import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct FileOperationRateTests {
    private func progress(
        taskID: String = "copy-1",
        processed: Int64?,
        total: Int64? = 100_000_000_000
    ) -> FileOperationProgress {
        FileOperationProgress(
            kind: .copyMove,
            taskID: taskID,
            isFinished: false,
            fractionCompleted: nil,
            processedSize: processed,
            totalSize: total,
            processedItemCount: nil,
            totalItemCount: nil,
            currentPath: nil,
            destinationPath: nil
        )
    }

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func computesTheRateAndTheTimeLeftFromSuccessiveSamples() throws {
        var rate = FileOperationRate()
        // 64 Mio par relevé, un relevé toutes les 2 s : 32 Mio/s.
        for step in 0..<5 {
            rate.record(
                progress(processed: Int64(step) * 67_108_864),
                at: start.addingTimeInterval(Double(step) * 2)
            )
        }

        let measured = try #require(rate.bytesPerSecond)
        #expect(abs(measured - 33_554_432) < 1)

        let last = progress(processed: 4 * 67_108_864, total: 40 * 67_108_864)
        let left = try #require(rate.remaining(for: last))
        // 36 relevés de 64 Mio restants à 32 Mio/s : 72 secondes.
        #expect(abs(left.components.seconds - 72) <= 1)
    }

    /// Une estimation qui s'affiche trop tôt saute de deux à quarante minutes ; mieux vaut
    /// ne rien afficher tant que la fenêtre n'a pas de quoi être stable.
    @Test func staysSilentUntilEnoughSamplesAreIn() {
        var rate = FileOperationRate()
        rate.record(progress(processed: 0), at: start)
        rate.record(progress(processed: 1_000_000), at: start.addingTimeInterval(1))
        #expect(rate.bytesPerSecond == nil)

        rate.record(progress(processed: 2_000_000), at: start.addingTimeInterval(2))
        rate.record(progress(processed: 3_000_000), at: start.addingTimeInterval(3))
        #expect(rate.bytesPerSecond != nil)
    }

    /// Une compression ne rapporte aucun volume traité : il n'y a rien à mesurer, et
    /// surtout rien à inventer.
    @Test func measuresNothingWhenTheNASReportsNoProcessedSize() {
        var rate = FileOperationRate()
        for step in 0..<6 {
            rate.record(progress(processed: nil), at: start.addingTimeInterval(Double(step)))
        }
        #expect(rate.bytesPerSecond == nil)
    }

    /// Une seconde opération ne doit pas hériter du débit de la précédente, ni d'un
    /// volume qui recule quand le NAS repart de zéro.
    @Test func startsOverWhenAnotherTaskTakesOver() {
        var rate = FileOperationRate()
        for step in 0..<5 {
            rate.record(
                progress(processed: Int64(step) * 100_000_000),
                at: start.addingTimeInterval(Double(step))
            )
        }
        #expect(rate.bytesPerSecond != nil)

        rate.record(progress(taskID: "copy-2", processed: 0), at: start.addingTimeInterval(5))
        #expect(rate.bytesPerSecond == nil)
    }

    /// Sous la minute, le compte à rebours n'a plus d'utilité : l'opération se termine
    /// avant d'avoir été lue à voix haute.
    @Test func hidesTheEstimateWhenTheEndIsSeconds() {
        var rate = FileOperationRate()
        for step in 0..<5 {
            rate.record(
                progress(processed: Int64(step) * 10_000_000),
                at: start.addingTimeInterval(Double(step))
            )
        }

        let almostDone = progress(processed: 40_000_000, total: 60_000_000)
        #expect(rate.remaining(for: almostDone) == nil)
    }
}
