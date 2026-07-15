//
//  DSMFileServiceSettingsService.swift
//  dsmaccess
//
//  Réglages des protocoles de partage de fichiers DSM.
//

import Foundation

@MainActor
final class DSMFileServiceSettingsService {
    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func isEnabled(_ service: FileService) async throws -> Bool? {
        let status = try await transport.value(
            api: DSMAPI(service.api),
            method: "get",
            as: FileServiceStatus.self
        )
        return status.enabled(for: service)
    }

    func set(_ service: FileService, enabled: Bool) async throws {
        try await transport.perform(
            api: DSMAPI(service.api),
            method: "set",
            parameters: [service.enableKey: .boolean(enabled)]
        )
    }
}
