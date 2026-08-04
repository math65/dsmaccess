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

    /// Applies the supplied settings. Turning encryption on or off answers with a task
    /// identifier and keeps working in the background, so the folder reaches its new state
    /// some time after this call returns.
    func update(_ changes: SharedFolderChanges) async throws {
        try await transport.perform(
            api: Self.shareAPI,
            method: "set",
            parameters: [
                "name": .string(changes.name),
                "shareinfo": try DSMParameter.json(changes),
            ]
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
