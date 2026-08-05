//
//  DSMShareService.swift
//  dsmaccess
//
//  Management of DSM shared folders.
//

import Foundation

@MainActor
final class DSMShareService {
    private static let shareAPI = DSMAPI("SYNO.Core.Share")
    private static let cryptoAPI = DSMAPI("SYNO.Core.Share.Crypto")
    private static let recycleBinAPI = DSMAPI("SYNO.Core.RecycleBin")

    /// Names of the `additional` groups, not of the fields they add: asking for
    /// `enable_recycle_bin` returns nothing at all, while `recyclebin` is what makes DSM send
    /// `enable_recycle_bin` and `recycle_bin_admin_only`. An unknown name is ignored in silence,
    /// so a typo here reads as "the NAS never sets this value".
    private static let listAdditional = [
        "recyclebin",
        "share_quota",
        "encryption",
        "hidden",
        "advance_setting",
        "enable_share_compress",
        "enable_share_cow",
        // The advanced permissions have no group of their own: each field is asked for by name.
        "disable_list",
        "disable_modify",
        "disable_download",
    ]

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func folders() async throws -> [SharedFolder] {
        let list = try await transport.read(
            api: Self.shareAPI,
            method: "list",
            parameters: ["additional": try DSMParameter.json(Self.listAdditional)],
            as: ShareList.self
        )
        return list.shares ?? []
    }

    func create(_ creation: SharedFolderCreation) async throws {
        try await transport.perform(
            api: Self.shareAPI,
            method: "create",
            parameters: [
                "name": .string(creation.name),
                "shareinfo": try DSMParameter.json(creation),
            ]
        )
    }

    /// Applies the supplied settings and hands back the identifier of the background task when
    /// DSM started one, which it does when encryption is turned on or off: the folder only
    /// reaches its new state once that task finishes.
    func update(_ changes: SharedFolderChanges) async throws -> String? {
        let result = try await transport.value(
            api: Self.shareAPI,
            method: "set",
            parameters: [
                "name": .string(changes.name),
                "shareinfo": try DSMParameter.json(changes),
            ],
            as: ShareUpdateResult.self
        )
        return result.taskID
    }

    /// Progress of the conversion started by `update`.
    func conversionStatus(taskID: String) async throws -> ShareConversionStatus {
        try await transport.read(
            api: Self.shareAPI,
            method: "move_status",
            parameters: ["task_id": .string(taskID)],
            as: ShareConversionStatus.self
        )
    }

    /// Stops a conversion in progress. DSM expects the `bg_taskid` parameter even though the
    /// web client always sends it empty.
    func cancelConversion(taskID: String) async throws {
        try await transport.perform(
            api: Self.shareAPI,
            method: "stop_move",
            parameters: ["task_id": .string(taskID)]
        )
    }

    /// Empties the recycle bin of one folder. The API is `SYNO.Core.RecycleBin`, and it takes
    /// the folder name under the parameter `id`.
    func emptyRecycleBin(name: String) async throws {
        try await transport.perform(
            api: Self.recycleBinAPI,
            method: "start",
            parameters: ["id": .string(name)]
        )
    }

    func delete(name: String) async throws {
        try await transport.perform(
            api: Self.shareAPI,
            method: "delete",
            parameters: ["name": try DSMParameter.json([name])]
        )
    }

    /// Locks an encrypted folder: DSM unmounts it and its contents become unreachable.
    /// The method really is called `encrypt`, even though the folder is already encrypted.
    func lock(name: String) async throws {
        try await transport.perform(
            api: Self.cryptoAPI,
            method: "encrypt",
            parameters: ["name": .string(name)]
        )
    }

    /// Mounts an encrypted folder again. A wrong key answers with code 3308.
    func unlock(name: String, key: String) async throws {
        try await transport.perform(
            api: Self.cryptoAPI,
            method: "decrypt",
            parameters: [
                "name": .string(name),
                "password": .string(key),
            ]
        )
    }
}
