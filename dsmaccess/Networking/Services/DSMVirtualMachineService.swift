//
//  DSMVirtualMachineService.swift
//  dsmaccess
//
//  Inventaire et alimentation des invités Virtual Machine Manager.
//

import Foundation

@MainActor
final class DSMVirtualMachineService {
    private static let guestAPI = DSMAPI("SYNO.Virtualization.API.Guest", preferredVersion: 1)
    private static let actionAPI = DSMAPI("SYNO.Virtualization.API.Guest.Action", preferredVersion: 1)

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func guests() async throws -> [VirtualMachine] {
        let result = try await transport.value(
            api: Self.guestAPI,
            method: "list",
            parameters: ["additional": .boolean(true)],
            as: VirtualMachineList.self
        )
        return result.guests
    }

    func perform(_ action: VirtualMachinePowerAction, guestID: String) async throws {
        let method: String
        switch action {
        case .powerOn: method = "poweron"
        case .shutdown: method = "shutdown"
        case .powerOff: method = "poweroff"
        }
        try await transport.perform(
            api: Self.actionAPI,
            method: method,
            parameters: ["guest_id": .string(guestID)]
        )
    }
}
