//
//  DSMFileServiceSettingsService.swift
//  dsmaccess
//
//  Settings for the DSM file sharing protocols.
//

import Foundation

@MainActor
final class DSMFileServiceSettingsService {
    private static let smbAPI = DSMAPI("SYNO.Core.FileServ.SMB")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func isEnabled(_ service: FileService) async throws -> Bool? {
        let status = try await transport.read(
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

    /// Every SMB setting, in one read. Both groups come from this single `get`.
    func smbSettings() async throws -> SMBSettings {
        try await transport.read(api: Self.smbAPI, method: "get", as: SMBSettings.self)
    }

    /// Applies what the main SMB screen holds.
    ///
    /// `logsTransfers` travels here rather than inside `SMBBasicSettings` because DSM reads it
    /// from another API entirely: leaving it out of the model makes it impossible to send a
    /// value that was never read, which would silently turn the transfer log off.
    ///
    /// Mutation: single-attempt path.
    func setSMBBasicSettings(_ settings: SMBBasicSettings, logsTransfers: Bool) async throws {
        try await transport.perform(
            api: Self.smbAPI,
            method: "set",
            parameters: [
                "enable_samba": .boolean(settings.isEnabled),
                "workgroup": .string(settings.workgroup),
                "disable_shadow_copy": .boolean(settings.deniesPreviousVersions),
                "enable_access_based_share_enum": .boolean(settings.hidesUnauthorizedShares),
                "smb_transfer_log_enable": .boolean(logsTransfers),
            ]
        )
    }

    /// Applies the advanced settings. The twenty-nine fields go out together, as the DSM
    /// dialog does: the measured call carries them all, including `enable_samba`, and sending
    /// a subset was never measured.
    ///
    /// Mutation: single-attempt path.
    func setSMBAdvancedSettings(_ settings: SMBAdvancedSettings, isEnabled: Bool) async throws {
        try await transport.perform(
            api: Self.smbAPI,
            method: "set",
            parameters: [
                "enable_samba": .boolean(isEnabled),
                "wins": .string(settings.winsServer),
                "smb_max_protocol": .integer(settings.maximumProtocol.rawValue),
                "smb_min_protocol": .integer(settings.minimumProtocol.rawValue),
                "smb_encrypt_transport": .integer(settings.transportEncryption.rawValue),
                "enable_server_signing": .integer(settings.serverSigning.rawValue),
                "enable_op_lock": .boolean(settings.opportunisticLocking),
                "enable_smb2_leases": .boolean(settings.smb2FileLeases),
                "enable_smb3_directory_leasing": .boolean(settings.smb3DirectoryLeasing),
                "enable_durable_handles": .boolean(settings.durableHandles),
                "enable_syno_catia": .boolean(settings.macCharacterConversion),
                "enable_fruit_locking": .boolean(settings.crossProtocolLockingWithAFP),
                "enable_local_master_browser": .boolean(settings.localMasterBrowser),
                "enable_dirsort": .boolean(settings.directorySorting),
                "enable_vetofile": .boolean(settings.vetoesFiles),
                "enable_delete_vetofiles": .boolean(settings.deletesDirectoriesHoldingVetoedFiles),
                "enable_symlink": .boolean(settings.symbolicLinks),
                "enable_widelink": .boolean(settings.wideLinks),
                "enable_reset_on_zero_vc": .boolean(settings.resetsOnZeroVirtualCircuit),
                "enable_enhance_log": .boolean(settings.debugLogging),
                "enable_mask": .boolean(settings.defaultUnixPermissions),
                "disable_strict_allocate": .boolean(settings.skipsDiskAllocation),
                "enable_ntlmv1_auth": .boolean(settings.ntlmv1Authentication),
                "enable_aio_read": .boolean(settings.asynchronousRead),
                "enable_synotify": .boolean(settings.subfolderChangeNotification),
                "enable_strict_sync": .boolean(settings.immediateSync),
                "enable_multichannel": .boolean(settings.smb3Multichannel),
                "syno_wildcard_search": .boolean(settings.wildcardSearchCache),
                "enable_perf_chart": .boolean(settings.performanceAnalysis),
            ]
        )
    }
}
