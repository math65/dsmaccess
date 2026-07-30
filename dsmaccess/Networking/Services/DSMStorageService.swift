//
//  DSMStorageService.swift
//  dsmaccess
//
//  Access to the NAS volumes, storage pools and disks.
//

import Foundation

@MainActor
final class DSMStorageService {
    private static let storageAPI = DSMAPI("SYNO.Storage.CGI.Storage")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func information() async throws -> StorageInfo {
        try await transport.read(
            api: Self.storageAPI,
            method: "load_info",
            as: StorageInfo.self
        )
    }
}
