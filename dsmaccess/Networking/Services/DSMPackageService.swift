//
//  DSMPackageService.swift
//  dsmaccess
//
//  Gestion des paquets installés, du catalogue et des réglages globaux.
//

import Foundation

@MainActor
final class DSMPackageService {
    private static let packageAPI = DSMAPI("SYNO.Core.Package")
    private static let serverAPI = DSMAPI("SYNO.Core.Package.Server")
    private static let controlAPI = DSMAPI("SYNO.Core.Package.Control")
    private static let uninstallationAPI = DSMAPI("SYNO.Core.Package.Uninstallation")
    private static let settingAPI = DSMAPI("SYNO.Core.Package.Setting")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func installedPackages() async throws -> [PackageInfo] {
        let list = try await transport.value(
            api: Self.packageAPI,
            method: "list",
            parameters: [
                "additional": try DSMParameter.json([
                    "status", "installed_info", "startable", "ctl_uninstall", "is_uninstall_pages",
                ])
            ],
            as: PackageList.self
        )
        return list.packages ?? []
    }

    func availableVersions() async throws -> [String: String] {
        var versions: [String: String] = [:]
        for loadsThirdPartyPackages in [false, true] {
            let list = try await transport.value(
                api: Self.serverAPI,
                method: "list",
                parameters: [
                    "blforcerefresh": .boolean(false),
                    "blloadothers": .boolean(loadsThirdPartyPackages),
                ],
                as: ServerPackageList.self
            )
            for package in list.packages ?? [] {
                if let identifier = package.id?.lowercased(), let version = package.version {
                    versions[identifier] = version
                }
            }
        }
        return versions
    }

    func setRunning(_ running: Bool, packageID: String) async throws {
        try await transport.perform(
            api: Self.controlAPI,
            method: running ? "start" : "stop",
            parameters: ["id": .string(packageID)]
        )
    }

    func uninstall(packageID: String) async throws {
        try await transport.perform(
            api: Self.uninstallationAPI,
            method: "uninstall",
            parameters: [
                "id": .string(packageID),
                "dsm_apps": "",
            ]
        )
    }

    func settings() async throws -> PackageSettings {
        try await transport.value(
            api: Self.settingAPI,
            method: "get",
            as: PackageSettings.self
        )
    }

    func setSettings(_ settings: PackageSettings) async throws {
        try await transport.perform(
            api: Self.settingAPI,
            method: "set",
            parameters: [
                "enable_autoupdate": .boolean(settings.enableAutoupdate),
                "autoupdateall": .boolean(settings.autoupdateAll),
                "autoupdateimportant": .boolean(settings.autoupdateImportant),
                "enable_dsm": .boolean(settings.enableDsm),
                "enable_email": .boolean(settings.enableEmail),
                "default_vol": .string(settings.defaultVol),
                "trust_level": .integer(settings.trustLevel),
                "update_channel": .string(settings.updateChannelBeta ? "beta" : "stable"),
            ]
        )
    }
}
