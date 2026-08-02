//
//  VirtualMachine.swift
//  dsmaccess
//
//  Virtual Machine Manager guests and their main components.
//

import Foundation

struct VirtualMachine: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let guestID: String
    let name: String
    let status: String
    let description: String?
    let storageID: String?
    let storageName: String?
    let vCPUCount: Int
    let memoryMiB: Int64?
    let autoRun: Bool
    let virtualDisks: [VirtualDisk]
    let networkInterfaces: [VirtualNetworkInterface]

    var id: String { guestID }
    var isRunning: Bool { status == "running" }
    var canStart: Bool { ["shutdown", "crashed"].contains(status) }
    var canStop: Bool { ["running", "booting"].contains(status) }
    var isTransitioning: Bool {
        ["booting", "shutting_down", "moving", "stor_migrating", "creating", "importing", "preparing"].contains(status)
    }

    /// The readable state lives here rather than in the view because the table sorts on it:
    /// sorting the raw DSM value would order the rows by their English identifier while the
    /// column shows the translation.
    var statusDescription: String {
        switch status {
        case "running": String(localized: "common.status.running")
        case "shutdown": String(localized: "vm.status.stopped")
        case "booting": String(localized: "vm.status.starting")
        case "shutting_down": String(localized: "common.status.stopping")
        case "inaccessible": String(localized: "common.status.unreachable")
        case "moving": String(localized: "common.operation.moving")
        case "stor_migrating": String(localized: "vm.status.migrating_storage")
        case "creating": String(localized: "common.label.creation")
        case "importing": String(localized: "vm.status.importing")
        case "preparing": String(localized: "vm.status.preparing")
        case "ha_standby": String(localized: "vm.status.ha_failover")
        case "crashed": String(localized: "vm.status.crashed")
        default: String(localized: "common.status.unknown")
        }
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableStatus: String { statusDescription }
    var sortableMemory: Int64 { memoryMiB ?? -1 }
    var sortableStorage: String { storageName ?? "" }
    var sortableDescription: String { description ?? "" }
    /// Sorted as text like `NASConnection.sortableTwoFactor`: `Bool` is not `Comparable`, and
    /// the column must be sortable like the others.
    var sortableAutoRun: String { autoRun ? "1" : "0" }

    enum CodingKeys: String, CodingKey {
        case guestID = "guest_id"
        case name = "guest_name"
        case status, description
        case storageID = "storage_id"
        case storageName = "storage_name"
        case vCPUCount = "vcpu_num"
        case memoryMiB = "memory"
        case autoRun = "autorun"
        case virtualDisks = "vdisks"
        case networkInterfaces = "vnics"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guestID = try values.requiredFlexString(.guestID)
        name = values.flexString(.name) ?? String(localized: "vm.machine.unnamed")
        status = values.flexString(.status) ?? "unknown"
        description = values.flexString(.description)
        storageID = values.flexString(.storageID)
        storageName = values.flexString(.storageName)
        vCPUCount = values.flexInt(.vCPUCount) ?? 0
        memoryMiB = values.flexInt64(.memoryMiB)
        autoRun = values.flexBool(.autoRun) ?? false
        virtualDisks = try values.decodeIfPresent([VirtualDisk].self, forKey: .virtualDisks) ?? []
        networkInterfaces = try values.decodeIfPresent([VirtualNetworkInterface].self, forKey: .networkInterfaces) ?? []
    }
}

struct VirtualDisk: nonisolated Decodable, Hashable, Sendable {
    let id: String?
    let name: String?
    let storageName: String?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "vdisk_id"
        case name = "vdisk_name"
        case storageName = "storage_name"
        case size
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.flexString(.id)
        name = values.flexString(.name)
        storageName = values.flexString(.storageName)
        size = values.flexInt64(.size)
    }
}

struct VirtualNetworkInterface: nonisolated Decodable, Hashable, Sendable {
    let id: String?
    let networkName: String?
    let macAddress: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case id = "vnic_id"
        case networkName = "network_name"
        case macAddress = "mac"
        case model
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.flexString(.id)
        networkName = values.flexString(.networkName)
        macAddress = values.flexString(.macAddress)
        model = values.flexString(.model)
    }
}

struct VirtualMachineList: nonisolated Decodable, Sendable {
    let guests: [VirtualMachine]

    enum CodingKeys: String, CodingKey { case guests }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guests = try values.decodeIfPresent([VirtualMachine].self, forKey: .guests) ?? []
    }
}

enum VirtualMachinePowerAction: Sendable {
    case powerOn
    case shutdown
    case powerOff
}
