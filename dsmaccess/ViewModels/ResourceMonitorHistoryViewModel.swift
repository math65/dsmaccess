//
//  ResourceMonitorHistoryViewModel.swift
//  dsmaccess
//
//  History tab of the resource monitor: the alerts the NAS recorded when a resource crossed a
//  threshold.
//
//  The log only fills up while recording is on, and DSM leaves it off by default. The state of
//  that setting is therefore loaded along with the entries: without it, an empty log would read
//  as a NAS without a single incident.
//

import Foundation
import Observation

@MainActor
@Observable
final class ResourceMonitorHistoryViewModel {
    /// The NAS keeps its log for as long as recording stays on. The page is large but bounded,
    /// and the screen says what it is not showing.
    static let pageLimit = 1000

    private(set) var entries: [ResourceMonitorLogEntry] = []
    /// Total returned by the NAS, which can exceed what is loaded.
    private(set) var totalCount = 0
    /// `nil` until the setting has been read: the screen concludes nothing before it knows.
    private(set) var historyEnabled: Bool?
    /// Number of alarm rules, read only when the log is empty. `nil` when the question does
    /// not arise or when the NAS refused to answer.
    private(set) var alarmRuleCount: Int?
    private(set) var isLoading = false
    /// True while the setting is being changed, to disarm the switch.
    private(set) var isUpdatingSetting = false
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if entries.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let enabled = try await session.withClient {
                try await $0.resourceMonitorHistoryEnabled()
            }
            let page = try await session.withClient {
                try await $0.resourceMonitorLogs(limit: Self.pageLimit)
            }
            guard generation == loadGeneration else { return }
            historyEnabled = enabled
            // Stable starting order, from the most recent alert to the oldest, like DSM. The
            // visible sort remains the one the user picks on the headers.
            entries = page.entries.sorted { $0.sortableDate > $1.sortableDate }
            totalCount = page.total ?? entries.count
            if entries.isEmpty, enabled {
                let count = await alarmRules()
                guard generation == loadGeneration else { return }
                alarmRuleCount = count
            } else {
                alarmRuleCount = nil
            }
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    /// Turns history recording on or off. Turning it on produces nothing retroactively: the
    /// message says so, so that a screen that stays empty is not mistaken for a setting with
    /// no effect.
    func setHistoryEnabled(_ enabled: Bool) async -> DSMOperationOutcome {
        isUpdatingSetting = true
        defer { isUpdatingSetting = false }
        do {
            try await session.withClient {
                try await $0.setResourceMonitorHistory(enabled: enabled)
            }
            historyEnabled = enabled
            await load()
            return .success(
                enabled
                    ? String(localized: "monitor.history.recording.on.announcement")
                    : String(localized: "monitor.history.recording.off.announcement")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.setting_change_failed", defaultValue: "Could not change the setting: \(reason)"))
        }
    }

    /// The log is empty: it remains to be seen whether that is for lack of an incident or for
    /// lack of a rule able to report one. A failure of this read is not surfaced as a screen
    /// error — the log itself did load, and the empty state then settles for the general
    /// message.
    private func alarmRules() async -> Int? {
        try? await session.withClient { try await $0.performanceAlarmRules().rules.count }
    }

    /// Timestamp rendered in the Mac's language. A dash when DSM sent a form we could not
    /// read: the alert stays listed, with no invented date.
    func dateText(for entry: ResourceMonitorLogEntry) -> String {
        guard let recordedAt = entry.recordedAt else { return "—" }
        return recordedAt.formatted(date: .abbreviated, time: .standard)
    }

    /// Severity spelled out. DSM sends its levels in English and translates them in its own
    /// client; an unknown value is passed through as-is rather than forced into an existing
    /// level.
    func levelText(for entry: ResourceMonitorLogEntry) -> String {
        switch entry.level {
        case .information: String(localized: "common.level.information")
        case .warning: String(localized: "common.level.warning")
        case .critical: String(localized: "common.level.critical")
        case .other(let raw): raw.isEmpty ? String(localized: "common.level.unknown") : raw
        }
    }

    func eventText(for entry: ResourceMonitorLogEntry) -> String {
        entry.event ?? String(localized: "monitor.history.alert.no_description")
    }

    /// True when the NAS keeps more than what was loaded.
    var isTruncated: Bool { totalCount > entries.count }

    var summary: String {
        if let errorMessage { return errorMessage }
        if historyEnabled == false {
            return String(localized: "monitor.history.recording.off.status")
        }
        if alarmRuleCount == 0 {
            return String(localized: "monitor.history.empty.no_rule.status")
        }
        if isTruncated {
            return String(localized: "monitor.history.count.filtered.announcement", defaultValue: "\(entries.count) of \(totalCount) recorded alerts shown")
        }
        return String(localized: "monitor.history.count.announcement", defaultValue: "\(entries.count) recorded alerts")
    }
}
