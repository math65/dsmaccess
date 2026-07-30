import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct ResourceMonitorLogTests {
    /// The web client reads this column with "Y/n/j G:i:s": month, day and hour are not padded
    /// to two digits. A rigid "yyyy/MM/dd HH:mm:ss" format would reject half the timestamps
    /// and the Date column would show a dash.
    @Test func readsATimestampWhoseComponentsAreNotPadded() throws {
        let payload = Data(#"""
        {"logs":[
          {"time":"2026/7/30 9:05:12","level":"Warning","event":"Utilisation du processeur supérieure à 80 %"},
          {"time":"2026/12/03 14:30:07","level":"Critical","event":"Utilisation de la mémoire supérieure à 90 %"}],
         "total":2}
        """#.utf8)

        let page = try JSONDecoder().decode(ResourceMonitorLogPage.self, from: payload)

        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 30
        components.hour = 9
        components.minute = 5
        components.second = 12
        #expect(page.entries.first?.recordedAt == Calendar.current.date(from: components))
        // The padded form is still read: DSM uses the same parser for both.
        #expect(page.entries.last?.recordedAt != nil)
    }

    /// Levels arrive in English and the client is what translates them. An unknown value is
    /// kept as is rather than forced into an existing level, which would display a severity
    /// the NAS did not send.
    @Test func mapsTheThreeLevelsDSMSendsAndKeepsTheRest() throws {
        let payload = Data(#"""
        {"logs":[
          {"time":"2026/7/30 9:00:00","level":"Information","event":"a"},
          {"time":"2026/7/30 9:00:01","level":"Warning","event":"b"},
          {"time":"2026/7/30 9:00:02","level":"Critical","event":"c"},
          {"time":"2026/7/30 9:00:03","level":"Emergency","event":"d"}],
         "total":4}
        """#.utf8)

        let levels = try JSONDecoder().decode(ResourceMonitorLogPage.self, from: payload)
            .entries.map(\.level)

        #expect(levels == [.information, .warning, .critical, .other("emergency")])
    }

    /// The Level column sorts by severity: ranking "Critical" before "Information" because C
    /// comes before I would make no sense when read.
    @Test func sortsLevelsBySeverityAndNotAlphabetically() {
        let levels: [ResourceMonitorLogEntry.Level] = [.critical, .information, .warning]

        #expect(levels.sorted { $0.severity < $1.severity } == [.information, .warning, .critical])
    }

    /// The NAS assigns no identifier, and two identical alerts can land in the same second.
    /// Without a distinct identity, the table would conflate the rows.
    @Test func distinguishesTwoIdenticalAlertsInTheSameSecond() throws {
        let payload = Data(#"""
        {"logs":[
          {"time":"2026/7/30 9:00:00","level":"Warning","event":"Charge du volume 1"},
          {"time":"2026/7/30 9:00:00","level":"Warning","event":"Charge du volume 1"}],
         "total":2}
        """#.utf8)

        let entries = try JSONDecoder().decode(ResourceMonitorLogPage.self, from: payload).entries

        #expect(entries.count == 2)
        #expect(entries[0].id != entries[1].id)
    }

    /// The common case on this NAS: recording is on but no alarm rule is defined, so no
    /// threshold can be crossed. The response is empty without being an error.
    @Test func survivesAnEmptyJournal() throws {
        let page = try JSONDecoder().decode(
            ResourceMonitorLogPage.self, from: Data(#"{"logs":[],"total":0}"#.utf8)
        )

        #expect(page.entries.isEmpty)
        #expect(page.total == 0)
    }

    /// The only setting DSM exposes. It decides whether the log fills up: reading it as false
    /// when it is true would present a NAS that is recording as a NAS that is not, and the
    /// other way round.
    @Test func readsTheHistoryRecordingSetting() throws {
        let enabled = try JSONDecoder().decode(
            ResourceMonitorSetting.self, from: Data(#"{"enable_history":true}"#.utf8)
        )
        let disabled = try JSONDecoder().decode(
            ResourceMonitorSetting.self, from: Data(#"{"enable_history":false}"#.utf8)
        )

        #expect(enabled.historyEnabled)
        #expect(!disabled.historyEnabled)
    }

    /// A setting missing from the response is not a disabled setting. Decoding fails rather
    /// than letting the screen claim that recording is off.
    @Test func refusesAResponseWithoutTheSetting() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ResourceMonitorSetting.self, from: Data(#"{}"#.utf8))
        }
    }
}
