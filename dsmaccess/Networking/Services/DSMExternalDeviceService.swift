//
//  DSMExternalDeviceService.swift
//  dsmaccess
//
//  USB and eSATA storage: listing, ejection, formatting and shared settings.
//

import Foundation

@MainActor
final class DSMExternalDeviceService {
    private static let settingAPI = DSMAPI("SYNO.Core.ExternalDevice.Storage.Setting", preferredVersion: 1)

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    /// Lists the devices of both connections, skipping the one the NAS does not publish.
    ///
    /// A model without an eSATA port simply has no such API, and that is not an error worth
    /// showing: the USB list still has to arrive.
    func devices() async throws -> [ExternalStorageDevice] {
        var all = [ExternalStorageDevice]()
        for connection in ExternalStorageConnection.allCases {
            guard transport.capabilities.supports(connection.apiName) else { continue }
            all.append(contentsOf: try await devices(on: connection))
        }
        return all
    }

    func devices(on connection: ExternalStorageConnection) async throws -> [ExternalStorageDevice] {
        // "all" is what DSM itself sends. Listing the fields explicitly returns a smaller
        // payload that silently drops the maker, the total size and the formattable flag.
        let list = try await transport.read(
            api: api(for: connection),
            method: "list",
            parameters: ["additional": try DSMParameter.json(["all"])],
            as: ExternalStorageDeviceList.self
        )
        return list.devices.map { device in
            var owned = device
            owned.connection = connection
            return owned
        }
    }

    /// Ejects a whole device. DSM has no way to eject a single partition.
    func eject(_ device: ExternalStorageDevice) async throws {
        try await transport.perform(
            api: api(for: device.connection),
            method: "eject",
            parameters: ["dev_id": try DSMParameter.json(device.devID)]
        )
    }

    /// Formats the entire device, destroying every partition it holds.
    ///
    /// Only the whole-disk option is offered. DSM can also format one chosen partition, but
    /// that path could not be measured — it stays disabled in DSM as soon as a device has a
    /// single partition — and a wrong guess here erases the wrong data.
    func format(
        _ device: ExternalStorageDevice,
        as fileSystem: ExternalStorageFileSystem
    ) async throws {
        try await transport.perform(
            api: api(for: device.connection),
            method: "format",
            parameters: [
                "dev_id": try DSMParameter.json(device.devID),
                "formatopt": try DSMParameter.json("entiredisk"),
                "filesystem": try DSMParameter.json(fileSystem.rawValue),
            ]
        )
    }

    func settings() async throws -> ExternalStorageSettings {
        try await transport.read(
            api: Self.settingAPI,
            method: "get",
            as: ExternalStorageSettings.self
        )
    }

    /// DSM expects the three switches together; sending one alone would reset the others.
    func updateSettings(_ settings: ExternalStorageSettings) async throws {
        try await transport.perform(
            api: Self.settingAPI,
            method: "set",
            parameters: [
                "forbid_usb": .boolean(settings.forbidsUSB),
                "non_admin_eject": .boolean(settings.allowsNonAdminEject),
                "delalloc": .boolean(settings.usesDelayedAllocation),
            ]
        )
    }

    private func api(for connection: ExternalStorageConnection) -> DSMAPI {
        DSMAPI(connection.apiName, preferredVersion: 1)
    }
}
