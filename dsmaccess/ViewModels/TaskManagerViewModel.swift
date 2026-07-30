//
//  TaskManagerViewModel.swift
//  dsmaccess
//
//  Task manager of the resource monitor: the services grouped the way DSM presents them, and
//  the most active processes. As with resources, a periodic refresh stays SILENT; only a
//  manual refresh announces.
//

import Foundation
import Observation

@MainActor
@Observable
final class TaskManagerViewModel {
    /// The NAS returns more than three hundred processes. Showing them all in a form would be
    /// unreadable with the keyboard as well as with a screen reader: only the most active ones
    /// are shown, and the screen says so instead of truncating silently.
    static let visibleProcessCount = 10

    private(set) var groups: [ProcessGroup] = []
    private(set) var processes: [SystemProcess] = []
    private(set) var totalProcessCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    var autoRefresh = false {
        didSet {
            guard autoRefresh != oldValue else { return }
            autoRefresh ? startAutoRefresh() : stopAutoRefresh(announce: true)
        }
    }

    private let session: SessionStore
    private var refreshTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if groups.isEmpty && processes.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            // The two reads are independent: running them together avoids waiting for two
            // round trips where the NAS can answer in parallel.
            async let loadedGroups = session.withClient { try await $0.processGroups() }
            async let loadedProcesses = session.withClient { try await $0.processes() }
            let (fetchedGroups, fetchedProcesses) = try await (loadedGroups, loadedProcesses)
            guard generation == loadGeneration else { return }
            // Sorted by memory and not by processor: the load of an idle service varies by a
            // hundredth of a point at each sample, and sorting on those differences reorders
            // the list at every refresh, which makes screen-reader navigation impractical.
            // Memory, by contrast, moves slowly. The visible sort remains the one the user
            // picks on the table headers.
            groups = fetchedGroups.sorted { lhs, rhs in
                let leftMemory = lhs.memoryBytes ?? -1
                let rightMemory = rhs.memoryBytes ?? -1
                if leftMemory != rightMemory { return leftMemory > rightMemory }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            totalProcessCount = fetchedProcesses.count
            processes = Array(
                fetchedProcesses
                    .sorted { ($0.cpuPercent ?? -1) > ($1.cpuPercent ?? -1) }
                    .prefix(Self.visibleProcessCount)
            )
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    private func startAutoRefresh() {
        VoiceOver.announce(
            String(localized: "common.status.automatic_refresh_on"),
            category: .automaticRefresh
        )
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await self?.load()
            }
        }
    }

    private func stopAutoRefresh(announce: Bool) {
        refreshTask?.cancel()
        refreshTask = nil
        if announce {
            VoiceOver.announce(
                String(localized: "common.status.automatic_refresh_off"),
                category: .automaticRefresh
            )
        }
    }

    func stop() { stopAutoRefresh(announce: false) }

    // MARK: - Formatted display

    /// A missing measurement is written "—": DSM literally returns "-" for the groups it does
    /// not measure, and writing zero instead would make a missing measurement look like an
    /// idle service.
    func cpuText(for group: ProcessGroup) -> String {
        guard let cpu = group.cpuPercent else { return "—" }
        return String(localized: "tasks.percent.value", defaultValue: "\(cpu.formatted(.number.precision(.fractionLength(1))))%")
    }

    func memoryText(for group: ProcessGroup) -> String {
        guard let bytes = group.memoryBytes else { return "—" }
        return bytes.formatted(.byteCount(style: .memory, spellsOutZero: false))
    }

    // MARK: - Measurements DSM does not display

    /// Processor time accumulated since the service started.
    func cpuTimeText(for group: ProcessGroup) -> String {
        guard let seconds = group.cpuTime, seconds >= 0 else { return "—" }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .narrow)
        )
    }

    func readRateText(for group: ProcessGroup) -> String {
        rateText(group.readBytesPerSecond)
    }

    func writeRateText(for group: ProcessGroup) -> String {
        rateText(group.writeBytesPerSecond)
    }

    /// A dash when DSM did not measure, a rate otherwise — including zero, which here is a
    /// measurement and not an absence: an idle service really does write nothing.
    private func rateText(_ bytesPerSecond: Int64?) -> String {
        guard let bytesPerSecond, bytesPerSecond >= 0 else { return "—" }
        let formatted = bytesPerSecond.formatted(.byteCount(style: .memory, spellsOutZero: false))
        return String(localized: "common.unit.per_second", defaultValue: "\(formatted)/s")
    }

    func cpuText(for process: SystemProcess) -> String {
        guard let cpu = process.cpuPercent else { return "—" }
        return String(localized: "common.unit.percent", defaultValue: "\(cpu)%")
    }

    /// Process memory comes in KiB, not in bytes like the memory of groups.
    func memoryText(for process: SystemProcess) -> String {
        guard let memoryKiB = process.memoryKiB, memoryKiB >= 0,
              let kib = Int64(exactly: memoryKiB) else { return "—" }
        let (bytes, overflow) = kib.multipliedReportingOverflow(by: 1024)
        guard !overflow else { return "—" }
        return bytes.formatted(.byteCount(style: .memory, spellsOutZero: false))
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "tasks.count.summary", defaultValue: "\(groups.count) services, \(totalProcessCount) processes")
    }
}
