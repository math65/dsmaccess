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
        // 64 MiB per sample, one sample every 2 s: 32 MiB/s.
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
        // 36 samples of 64 MiB left at 32 MiB/s: 72 seconds.
        #expect(abs(left.components.seconds - 72) <= 1)
    }

    /// An estimate shown too early jumps from two to forty minutes; better to show nothing
    /// as long as the window has nothing to make it stable.
    @Test func staysSilentUntilEnoughSamplesAreIn() {
        var rate = FileOperationRate()
        rate.record(progress(processed: 0), at: start)
        rate.record(progress(processed: 1_000_000), at: start.addingTimeInterval(1))
        #expect(rate.bytesPerSecond == nil)

        rate.record(progress(processed: 2_000_000), at: start.addingTimeInterval(2))
        rate.record(progress(processed: 3_000_000), at: start.addingTimeInterval(3))
        #expect(rate.bytesPerSecond != nil)
    }

    /// A compression reports no processed volume: there is nothing to measure, and above all
    /// nothing to invent.
    @Test func measuresNothingWhenTheNASReportsNoProcessedSize() {
        var rate = FileOperationRate()
        for step in 0..<6 {
            rate.record(progress(processed: nil), at: start.addingTimeInterval(Double(step)))
        }
        #expect(rate.bytesPerSecond == nil)
    }

    /// A second operation must not inherit the previous one's rate, nor a volume that goes
    /// backwards when the NAS starts again from zero.
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

    /// A near end is still information: the estimate is returned as is, and it is up to the
    /// display to say "less than a minute" rather than counting off seconds.
    @Test func stillEstimatesWhenTheEndIsSeconds() throws {
        var rate = FileOperationRate()
        for step in 0..<5 {
            rate.record(
                progress(processed: Int64(step) * 10_000_000),
                at: start.addingTimeInterval(Double(step))
            )
        }

        let almostDone = progress(processed: 40_000_000, total: 60_000_000)
        let left = try #require(rate.remaining(for: almostDone))
        #expect(left < .seconds(60))
        #expect(left > .zero)
    }

    /// Without a total size — the case of a compression — there is nothing to estimate.
    @Test func estimatesNothingWithoutATotalSize() {
        var rate = FileOperationRate()
        for step in 0..<5 {
            rate.record(
                progress(processed: Int64(step) * 10_000_000, total: nil),
                at: start.addingTimeInterval(Double(step))
            )
        }
        #expect(rate.bytesPerSecond != nil)
        #expect(rate.remaining(for: progress(processed: 40_000_000, total: nil)) == nil)
    }
}
