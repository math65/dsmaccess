//
//  VirtualMachinesViewModel.swift
//  dsmaccess
//
//  State and power control of virtual machines.
//

import Foundation
import Observation

@MainActor
@Observable
final class VirtualMachinesViewModel {
    private(set) var machines: [VirtualMachine] = []
    private(set) var isLoading = false
    private(set) var busyIDs: Set<String> = []
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = !silently
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let result = try await session.withClient { try await $0.listVirtualMachines() }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            guard generation == loadGeneration else { return }
            machines = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func perform(_ action: VirtualMachinePowerAction, on machine: VirtualMachine) async -> DSMOperationOutcome {
        busyIDs.insert(machine.id)
        defer { busyIDs.remove(machine.id) }

        do {
            try await session.withClient {
                try await $0.performVirtualMachineAction(action, guestID: machine.guestID)
            }
            await load(silently: true)
            switch action {
            case .powerOn: return .success(String(localized: "vm.start.requested.announcement", defaultValue: "Start requested for \(machine.name)"))
            case .shutdown: return .success(String(localized: "vm.shutdown.requested.announcement", defaultValue: "Graceful shutdown requested for \(machine.name)"))
            case .powerOff: return .success(String(localized: "vm.force_off.requested.announcement", defaultValue: "Forced power off requested for \(machine.name)"))
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(machine.name): \(reason)"))
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let running = machines.filter(\.isRunning).count
        return String(localized: "vm.summary.counts", defaultValue: "\(machines.count) virtual machines, \(running) running")
    }
}
