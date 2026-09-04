//
//  PerformanceAlarmViewModel.swift
//  dsmaccess
//
//  Performance alarm tab: the thresholds beyond which the NAS records an alert in its
//  history. Without a rule that log stays empty no matter what happens — this screen is
//  what gives it something to record.
//

import Foundation
import Observation

@MainActor
@Observable
final class PerformanceAlarmViewModel {
    private(set) var rules: [PerformanceAlarmRule] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// Rules with a toggle or a delete in flight, so their controls can be disarmed.
    private(set) var busyIDs: Set<String> = []
    /// The NAS allows internal-use rules, reserved for Synology. Read so we do not hide a
    /// rule that the NAS itself would display.
    private(set) var supportsInternalUse = false

    /// Targets offered by the form, loaded only when the sheet opens: they are of no use
    /// until a rule is being composed.
    private(set) var services: [Target] = []
    private(set) var volumes: [Target] = []
    private(set) var isLoadingTargets = false

    /// A selectable target: what the NAS expects, and what the user reads.
    struct Target: Identifiable, Sendable, Equatable {
        let value: String
        let label: String

        var id: String { value }
    }

    /// Readable label for each service, looked up by unit name. In a rule the NAS sometimes
    /// returns a key from its own catalogue instead of the name: the service list, on the
    /// other hand, carries the label the user picked in the form.
    private var serviceLabels: [String: String] = [:]

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if rules.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page = try await session.withClient { try await $0.performanceAlarmRules() }
            guard generation == loadGeneration else { return }

            // Service labels are resolved **before** the rules are published: the table must
            // appear already named, not rename itself under the user's fingers a fraction of
            // a second later. Their absence is not an error — the unit name stays readable.
            if page.rules.contains(where: { $0.kind == .service }), serviceLabels.isEmpty {
                let loaded = await loadServices()
                guard generation == loadGeneration else { return }
                services = loaded
                serviceLabels = Dictionary(
                    loaded.map { ($0.value, $0.label) },
                    uniquingKeysWith: { first, _ in first }
                )
            }

            // Stable starting order: critical rules first, then by target. The visible sort
            // remains the one the user picks on the column headers.
            rules = page.rules.sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity.rawValue > rhs.severity.rawValue }
                return lhs.sortableTarget.localizedStandardCompare(rhs.sortableTarget) == .orderedAscending
            }
            supportsInternalUse = page.supportsInternalUse
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    /// Turns a rule on or off. The NAS accepts a batch; one rule at a time is enough here and
    /// makes the outcome announceable without ambiguity.
    func setEnabled(_ rule: PerformanceAlarmRule, _ enabled: Bool) async -> DSMOperationOutcome {
        busyIDs.insert(rule.id)
        defer { busyIDs.remove(rule.id) }
        do {
            try await session.withClient {
                try await $0.setPerformanceAlarmRules([(id: rule.id, enabled: enabled)])
            }
            await load()
            return .success(
                enabled
                    ? String(localized: "alarm.rule.turned_on.announcement", defaultValue: "Rule turned on: \(description(of: rule))")
                    : String(localized: "alarm.rule.turned_off.announcement", defaultValue: "Rule turned off: \(description(of: rule))")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "alarm.rule.toggle.error", defaultValue: "Could not change the rule state: \(reason)"))
        }
    }

    func delete(_ selection: [PerformanceAlarmRule]) async -> DSMOperationOutcome {
        guard !selection.isEmpty else { return .cancelled }
        let ids = selection.map(\.id)
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }
        do {
            try await session.withClient { try await $0.deletePerformanceAlarmRules(ids: ids) }
            await load()
            if selection.count == 1, let only = selection.first {
                return .success(String(localized: "alarm.rule.deleted.announcement", defaultValue: "Rule deleted: \(description(of: only))"))
            }
            return .success(String(localized: "alarm.rules.delete.announcement", defaultValue: "\(selection.count) rules deleted"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.delete_failed", defaultValue: "Delete failed: \(reason)"))
        }
    }

    func save(_ draft: PerformanceAlarmRuleDraft) async -> DSMOperationOutcome {
        do {
            try await session.withClient { try await $0.savePerformanceAlarmRule(draft) }
            await load()
            return .success(
                draft.isCreation
                    ? String(localized: "alarm.rule.created.announcement")
                    : String(localized: "alarm.rule.updated.announcement")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            // The NAS identifies a rule by its kind, target, resource and severity: two rules
            // that share them collide, whatever their thresholds are.
            if case .apiError(Self.ruleAlreadyExistsCode, _)? = error as? DSMError {
                return .failure(
                    String(localized: "alarm.rule.error.duplicate")
                )
            }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.save_failed", defaultValue: "Saving failed: \(reason)"))
        }
    }

    /// Code returned by the NAS when the quadruple identifying the rule is already taken.
    private static let ruleAlreadyExistsCode = 6106

    /// Loads the selectable targets. The two reads are independent: a NAS with no readable
    /// volume must still be able to compose a service rule, and the other way round.
    func loadTargets() async {
        isLoadingTargets = true
        defer { isLoadingTargets = false }
        if services.isEmpty { services = await loadServices() }
        volumes = await loadVolumes()
    }

    private func loadServices() async -> [Target] {
        do {
            let groups = try await session.withClient { try await $0.processGroups() }
            return groups
                .compactMap { group in
                    // DSM leaves its own internal slice out of the list of monitorable
                    // services; it names nothing the user would recognise.
                    guard let unitName = group.unitName, unitName != Self.internalSlice else {
                        return nil
                    }
                    return Target(value: unitName, label: group.displayName)
                }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        } catch {
            return []
        }
    }

    private func loadVolumes() async -> [Target] {
        do {
            let storage = try await session.withClient { try await $0.storageInfo() }
            return (storage.volumes ?? []).compactMap { volume in
                guard let path = volume.mountPath, !path.isEmpty else { return nil }
                return Target(value: path, label: volume.desc?.isEmpty == false ? volume.desc! : path)
            }
        } catch {
            return []
        }
    }

    /// Slice that DSM itself excludes from the monitorable services.
    private static let internalSlice = "syno_dsm_internal.slice"

    // MARK: - Presentation

    /// The rule in one sentence, as it reads in the table and is announced after an action.
    /// One complete key per case rather than an assembly of fragments: word order is not the
    /// same from one language to another.
    func description(of rule: PerformanceAlarmRule) -> String {
        let threshold = rule.threshold
        switch (rule.kind, rule.resource) {
        case (.system, .processorUsage):
            return String(localized: "alarm.rule.summary.processor", defaultValue: "Processor above \(threshold) %")
        case (.system, .loadAverageOneMinute):
            return String(localized: "alarm.rule.summary.load_average_1m", defaultValue: "1-minute load average above \(threshold)")
        case (.system, .loadAverageFiveMinutes):
            return String(localized: "alarm.rule.summary.load_average_5m", defaultValue: "5-minute load average above \(threshold)")
        case (.system, .loadAverageFifteenMinutes):
            return String(localized: "alarm.rule.summary.load_average_15m", defaultValue: "15-minute load average above \(threshold)")
        case (.system, .memory):
            return String(localized: "alarm.rule.summary.memory_usage", defaultValue: "Memory above \(threshold) %")
        case (.system, .graphicsUsage):
            return String(localized: "alarm.rule.summary.graphics_processor", defaultValue: "Graphics processor above \(threshold) %")
        case (.service, .processorUsage):
            return String(localized: "alarm.rule.summary.processor_target", defaultValue: "\(targetName(of: rule)): processor above \(threshold) %")
        case (.service, .memory):
            return String(localized: "alarm.rule.summary.memory_used_target", defaultValue: "\(targetName(of: rule)): memory above \(threshold) MB")
        case (.service, .diskActivity):
            return String(localized: "alarm.rule.summary.disk_throughput_target", defaultValue: "\(targetName(of: rule)): disk activity above \(threshold) MB/s")
        case (.volume, .diskActivity):
            return String(localized: "alarm.rule.summary.disk_usage_target", defaultValue: "\(targetName(of: rule)): disk activity above \(threshold) %")
        case (.iSCSI, .networkLatency):
            return String(localized: "alarm.rule.summary.network_latency_target", defaultValue: "\(targetName(of: rule)): network latency above \(threshold) ms")
        case (.iSCSI, .ioLatency):
            return String(localized: "alarm.rule.summary.access_latency_target", defaultValue: "\(targetName(of: rule)): access latency above \(threshold) ms")
        case (.internalUse, .rootPartition):
            return String(localized: "alarm.rule.summary.system_partition", defaultValue: "System partition above \(threshold) %")
        case (.internalUse, .temporaryDirectory):
            return String(localized: "alarm.rule.summary.temporary_folder", defaultValue: "Temporary folder above \(threshold) %")
        case (.internalUse, .coredumpCount):
            return String(localized: "alarm.rule.summary.core_dump_files", defaultValue: "More than \(threshold) core dump files")
        default:
            // The NAS returned a combination its own client does not offer: the rule stays
            // listed and deletable, with what we know about it.
            return String(localized: "alarm.rule.summary.unknown_resource", defaultValue: "Threshold of \(threshold) on an unknown resource")
        }
    }

    /// The target name as it was picked in the form, when the service list makes it possible
    /// to find it again: the NAS sometimes returns a catalogue key instead, and reading
    /// "synobackupd" after choosing "Backup service" would be disorienting.
    private func targetName(of rule: PerformanceAlarmRule) -> String {
        if rule.kind == .service, let label = serviceLabels[rule.target] {
            return label
        }
        return rule.displayTarget ?? String(localized: "alarm.target.unknown")
    }

    func kindText(_ kind: PerformanceAlarmRule.Kind) -> String {
        switch kind {
        case .system: String(localized: "common.label.system")
        case .service: String(localized: "common.column.service")
        case .iSCSI: String(localized: "alarm.target.iscsi_lun")
        case .volume: String(localized: "common.column.volume")
        case .internalUse: String(localized: "alarm.target.internal_use")
        }
    }

    func severityText(_ severity: PerformanceAlarmRule.Severity) -> String {
        switch severity {
        case .warning: String(localized: "common.level.warning")
        case .critical: String(localized: "common.level.critical")
        }
    }

    func resourceText(_ resource: PerformanceAlarmRule.Resource, for kind: PerformanceAlarmRule.Kind) -> String {
        switch (kind, resource) {
        case (_, .processorUsage): String(localized: "alarm.resource.processor_usage")
        case (_, .loadAverageOneMinute): String(localized: "alarm.resource.load_average_1m")
        case (_, .loadAverageFiveMinutes): String(localized: "alarm.resource.load_average_5m")
        case (_, .loadAverageFifteenMinutes): String(localized: "alarm.resource.load_average_15m")
        case (.service, .memory): String(localized: "alarm.resource.memory_used")
        case (_, .memory): String(localized: "alarm.resource.memory_usage")
        case (.volume, .diskActivity): String(localized: "alarm.resource.disk_access_usage")
        case (_, .diskActivity): String(localized: "alarm.resource.disk_throughput")
        case (_, .networkLatency): String(localized: "alarm.resource.network_latency")
        case (_, .ioLatency): String(localized: "alarm.resource.access_latency")
        case (_, .rootPartition): String(localized: "alarm.resource.system_partition")
        case (_, .temporaryDirectory): String(localized: "alarm.resource.temporary_folder")
        case (_, .coredumpCount): String(localized: "alarm.resource.core_dump_files")
        case (_, .graphicsUsage): String(localized: "alarm.resource.graphics_processor_usage")
        }
    }

    /// The unit written next to the threshold field. Empty when the quantity has none: a load
    /// average or a count reads without a unit.
    func unitText(_ unit: PerformanceAlarmRule.Unit) -> String {
        switch unit {
        case .percent: "%"
        case .megabytes: String(localized: "alarm.unit.megabytes")
        case .megabytesPerSecond: String(localized: "alarm.unit.megabytes_per_second")
        case .milliseconds: String(localized: "alarm.unit.milliseconds")
        case .none: ""
        }
    }

    func canModify(_ rule: PerformanceAlarmRule) -> Bool {
        rule.kind.isEditable && !busyIDs.contains(rule.id)
    }

    func isBusy(_ rule: PerformanceAlarmRule) -> Bool { busyIDs.contains(rule.id) }

    var summary: String {
        if let errorMessage { return errorMessage }
        if rules.isEmpty { return String(localized: "common.empty.alarm_rules") }
        let active = rules.filter(\.isEnabled).count
        return String(localized: "alarm.rules.summary", defaultValue: "\(rules.count) alarm rules, \(active) on")
    }
}
