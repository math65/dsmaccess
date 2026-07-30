//
//  SystemResourcesViewModel.swift
//  dsmaccess
//
//  Loads and exposes the NAS's instantaneous measurements (processor, memory, network).
//  Handles an optional automatic refresh (5 s loop), designed for VoiceOver: periodic
//  updates are SILENT (no announcement spam); only a manual refresh re-announces the
//  summary.
//

import Foundation
import Observation

@MainActor
@Observable
final class SystemResourcesViewModel {
    private(set) var usage: ResourceUsage?
    private(set) var isLoading = false
    var errorMessage: String?

    /// Periodic refresh. Driven by the view's Toggle; starts/stops the loop.
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

    /// Reloads the measurements. `announce == true` re-announces the summary (manual refresh).
    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if usage == nil { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { try await $0.resourceUsage() }
            guard generation == loadGeneration else { return }
            usage = result
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    // MARK: - Automatic refresh

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
                await self?.load()   // silent: no announcement on every tick
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

    /// Stops the loop without announcing (called when the screen goes away).
    func stop() {
        stopAutoRefresh(announce: false)
    }

    // MARK: - Formatted display

    /// Total processor load as a percentage (user + system + other).
    var cpuPercent: Int? {
        guard let cpu = usage?.cpu else { return nil }
        let values = [cpu.userLoad, cpu.systemLoad, cpu.otherLoad]
            .compactMap { $0 }
            .filter { (0...100).contains($0) }
        return values.isEmpty ? nil : min(values.reduce(0, +), 100)
    }

    var cpuText: String {
        cpuPercent.map { String(localized: "common.unit.percent", defaultValue: "\($0)%") } ?? "—"
    }

    /// Split between user time and system time. DSM sometimes puts the whole load in
    /// `other_load` and returns zero for the other two — observed on a DS920+ at 27 % load,
    /// then "user 6 %, system 31 %" a few minutes later on the same machine. So it is a
    /// transient state, not a property of the model. When both values are zero, the line
    /// disappears: "User 0 %, system 0 %" under a non-zero load reads as a broken measurement
    /// and contradicts the line above.
    var cpuDetailText: String? {
        guard let cpu = usage?.cpu, let user = cpu.userLoad, let system = cpu.systemLoad else { return nil }
        guard user > 0 || system > 0 else { return nil }
        return String(localized: "resources.cpu.user_system.summary", defaultValue: "User \(user)%, system \(system)%")
    }

    var memoryPercent: Int? {
        usage?.memory?.realUsage.flatMap { (0...100).contains($0) ? $0 : nil }
    }

    var memoryText: String {
        memoryPercent.map { String(localized: "common.unit.percent", defaultValue: "\($0)%") } ?? "—"
    }

    /// "0.64 GB of 3.68 GB" (DSM sizes are in KiB → converted to bytes). The volume shown
    /// excludes the cache, like the percentage just above: both lines must tell the same
    /// story.
    var memoryDetailText: String? {
        guard let mem = usage?.memory,
              let total = mem.totalReal,
              total >= 0,
              let totalKiB = Int64(exactly: total),
              let used = mem.usedReal,
              (0...total).contains(used),
              let usedKiB = Int64(exactly: used) else { return nil }
        let (usedBytes, usedOverflow) = usedKiB.multipliedReportingOverflow(by: 1024)
        let (totalBytes, totalOverflow) = totalKiB.multipliedReportingOverflow(by: 1024)
        guard !usedOverflow, !totalOverflow else { return nil }
        return String(localized: "common.format.value_of_total", defaultValue: "\(usedBytes.formatted(.byteCount(style: .memory))) of \(totalBytes.formatted(.byteCount(style: .memory)))")
    }

    var swapText: String? {
        guard let swap = usage?.memory?.swapUsage, (0...100).contains(swap) else { return nil }
        return String(localized: "common.unit.percent", defaultValue: "\(swap)%")
    }

    /// The synthetic "total" interface (falls back to the first one if absent).
    private var totalInterface: ResourceUsage.Interface? {
        usage?.network?.first { $0.device == "total" } ?? usage?.network?.first
    }

    var networkDownText: String { rateText(totalInterface?.rx) }
    var networkUpText: String { rateText(totalInterface?.tx) }

    /// `spellsOutZero` disabled: the default style writes "Zero kB", which reads badly in a
    /// line of measurements and sounds even worse.
    private func rateText(_ bytesPerSecond: Int?) -> String {
        guard let bytesPerSecond, bytesPerSecond >= 0 else { return "—" }
        let formatted = Int64(bytesPerSecond)
            .formatted(.byteCount(style: .memory, spellsOutZero: false))
        return String(localized: "common.unit.per_second", defaultValue: "\(formatted)/s")
    }

    /// Load averages over one, five and fifteen minutes. Left out as long as DSM returns none
    /// of them, rather than shown as zero, which would read as a measurement.
    var loadAverageText: String? {
        guard let cpu = usage?.cpu,
              let one = cpu.oneMinuteLoad,
              let five = cpu.fiveMinuteLoad,
              let fifteen = cpu.fifteenMinuteLoad else { return nil }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        return String(
            localized: "resources.load_average.summary",
            defaultValue: "\(one.formatted(format)) over 1 minute, \(five.formatted(format)) over 5 minutes, \(fifteen.formatted(format)) over 15 minutes"
        )
    }

    /// Physical disks, excluding the aggregate entry DSM keeps separately. Sorted by name: the
    /// NAS returns them in an order of its own (Drive 4, 3, 1, 2), confusing both to read and
    /// to traverse with the keyboard.
    var disks: [ResourceUsage.Device] {
        (usage?.disk?.devices ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var diskTotal: ResourceUsage.Device? { usage?.disk?.total }
    var volumes: [ResourceUsage.Device] { usage?.space?.devices ?? [] }

    /// "14 %, 859 kB/s read, 16 kB/s written". The utilization rate alone does not say whether
    /// the disk is struggling on reads or on writes.
    func activityText(for device: ResourceUsage.Device) -> String {
        let read = rateText(device.readBytesPerSecond)
        let write = rateText(device.writeBytesPerSecond)
        guard let utilization = device.utilization, (0...100).contains(utilization) else {
            return String(localized: "resources.disk.throughput.summary", defaultValue: "\(read) read, \(write) written")
        }
        return String(localized: "resources.disk.usage_and_throughput.summary", defaultValue: "\(utilization)%, \(read) read, \(write) written")
    }

    /// Summary announced to VoiceOver after a manual refresh.
    var summary: String {
        if let errorMessage { return errorMessage }
        let cpu = cpuPercent.map(String.init) ?? "—"
        let mem = memoryPercent.map(String.init) ?? "—"
        return String(localized: "resources.overview.cpu_memory.summary", defaultValue: "Processor \(cpu)%, memory \(mem)%")
    }
}
