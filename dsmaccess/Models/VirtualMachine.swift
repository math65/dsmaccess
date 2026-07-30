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
