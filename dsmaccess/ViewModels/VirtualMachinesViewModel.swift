//
//  VirtualMachinesViewModel.swift
//  dsmaccess
//
//  État et alimentation des machines virtuelles.
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

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        if !silently { isLoading = true }
        errorMessage = nil
        defer { isLoading = false }

        do {
            machines = try await session.withClient { try await $0.listVirtualMachines() }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func perform(_ action: VirtualMachinePowerAction, on machine: VirtualMachine) async -> String {
        busyIDs.insert(machine.id)
        defer { busyIDs.remove(machine.id) }

        do {
            try await session.withClient {
                try await $0.performVirtualMachineAction(action, guestID: machine.guestID)
            }
            await load(silently: true)
            switch action {
            case .powerOn: return String(localized: "Démarrage demandé pour \(machine.name)")
            case .shutdown: return String(localized: "Arrêt propre demandé pour \(machine.name)")
            case .powerOff: return String(localized: "Extinction forcée demandée pour \(machine.name)")
            }
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec pour \(machine.name) : \(reason)")
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let running = machines.filter(\.isRunning).count
        return String(localized: "\(machines.count) machines virtuelles, \(running) en fonctionnement")
    }
}
