import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DownloadTaskTests {
    /// Shape observed on the DS920+ under DSM 7.4. The transfer counters live under
    /// `additional`, which DSM only fills in when the request asked for them.
    @Test func readsATaskWithItsTransferCounters() throws {
        let task = try decode(#"""
        {"id":"dbid_1","title":"archive.zip","type":"http","username":"testeur",
         "size":4096,"status":"downloading",
         "additional":{"detail":{"destination":"downloads"},
                       "transfer":{"size_downloaded":1024,"size_uploaded":16,
                                   "speed_download":500,"speed_upload":8}}}
        """#)

        #expect(task.downloaded == 1024)
        #expect(task.downloadSpeed == 500)
        #expect(task.uploadSpeed == 8)
        #expect(task.destination == "downloads")
        #expect(task.progress == 0.25)
    }

    /// The table sorts the state column on the displayed text, so two states that came out
    /// with the same wording would silently merge into one group. A state DSM adds later must
    /// land on the unknown wording rather than on an empty cell.
    @Test func givesEveryKnownStateItsOwnWording() throws {
        let states = [
            "waiting", "downloading", "paused", "finishing", "finished",
            "hash_checking", "seeding", "filehosting_waiting", "extracting", "error",
        ]

        let wordings = try states.map { try decode(status: $0).statusDescription }

        let distinctWordings = Set(wordings).count
        let hasEmptyWording = wordings.contains(where: \.isEmpty)
        #expect(distinctWordings == states.count)
        #expect(hasEmptyWording == false)

        let added = try decode(status: "a_state_dsm_added").statusDescription
        #expect(added == String(localized: "common.status.unknown"))
    }

    /// A task whose size the NAS has not reported has no progress at all, which is not the
    /// same thing as a progress of zero. Sorting the column must keep the two apart instead
    /// of showing an unstarted download as if it were as far along as an unmeasurable one.
    @Test func keepsAnUnknownProgressApartFromZero() throws {
        let unknown = try decode(status: "waiting", size: 0)
        let started = try decode(status: "downloading", size: 4096)

        #expect(unknown.progress == nil)
        #expect(unknown.sortableProgress < started.sortableProgress)
    }

    /// Sorting must not fail on the rows DSM leaves incomplete: without `additional`, the
    /// destination is absent and its column would otherwise have nothing to sort on.
    @Test func sortsATaskThatCarriesNoDetail() throws {
        let task = try decode(status: "finished")

        #expect(task.destination == nil)
        #expect(task.sortableDestination.isEmpty)
    }

    private func decode(_ json: String) throws -> DownloadTask {
        try JSONDecoder().decode(DownloadTask.self, from: Data(json.utf8))
    }

    private func decode(status: String, size: Int64 = 4096) throws -> DownloadTask {
        try decode(#"{"id":"dbid_1","title":"archive.zip","size":\#(size),"status":"\#(status)"}"#)
    }
}
