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
    private static let installationAPI = DSMAPI(
        "SYNO.Core.Package.Installation",
        preferredVersion: 1
    )

    private let transport: DSMTransport
    private let updatePollInterval: Duration
    private let updatePollLimit: Int

    init(
        transport: DSMTransport,
        updatePollInterval: Duration = .milliseconds(1200),
        updatePollLimit: Int = 900
    ) {
        self.transport = transport
        self.updatePollInterval = updatePollInterval
        self.updatePollLimit = updatePollLimit
    }

    func capabilities() -> PackageCenterCapabilities {
        let apis = [
            Self.packageAPI,
            Self.serverAPI,
            Self.installationAPI,
            Self.controlAPI,
            Self.uninstallationAPI,
            Self.settingAPI,
        ]
        let maximumVersions = Dictionary(
            uniqueKeysWithValues: apis.compactMap { api in
                transport.capabilities.entry(for: api.name).map { (api.name, $0.maxVersion) }
            }
        )
        return PackageCenterCapabilities(
            canListInstalledPackages: transport.capabilities.supports(Self.packageAPI),
            canBrowseCatalog: transport.capabilities.supports(Self.serverAPI),
            canInstallVerifiedUpdates: transport.capabilities.supports(Self.installationAPI),
            canControlPackages: transport.capabilities.supports(Self.controlAPI),
            canUninstallPackages: transport.capabilities.supports(Self.uninstallationAPI),
            canManageSettings: transport.capabilities.supports(Self.settingAPI),
            maximumVersions: maximumVersions
        )
    }

    func installedPackages() async throws -> [PackageInfo] {
        let list = try await transport.read(
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

    func availableUpdates() async throws -> [String: PackageUpdate] {
        let catalog = try await officialCatalog()
        return catalog.reduce(into: [:]) { updates, update in
            updates[update.packageID.lowercased()] = update
        }
    }

    func officialCatalog(forceRefresh: Bool = false) async throws -> [PackageUpdate] {
        let list = try await transport.read(
            api: Self.serverAPI,
            method: "list",
            parameters: [
                "blforcerefresh": .boolean(forceRefresh),
                "blloadothers": .boolean(false),
            ],
            as: ServerPackageList.self
        )

        let uniquePackages = (list.packages ?? [])
            .compactMap(packageUpdate)
            .reduce(into: [String: PackageUpdate]()) { packages, package in
                packages[package.id] = package
            }
            .values
        return uniquePackages.sorted { left, right in
            let nameOrder = left.packageID.localizedStandardCompare(right.packageID)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return left.version.localizedStandardCompare(right.version) == .orderedAscending
        }
    }

    func upgrade(_ update: PackageUpdate) async throws {
        try await upgrade(update, progress: { _ in })
    }

    func upgrade(
        _ update: PackageUpdate,
        progress: (PackageOperationProgress) -> Void
    ) async throws {
        guard !update.packageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              update.fileSize > 0,
              update.packageType >= 0,
              Self.isValidChecksum(update.checksum),
              update.downloadURL.scheme?.lowercased() == "https",
              update.downloadURL.host != nil else {
            throw DSMError.invalidResponse
        }

        let task = try await transport.value(
            api: Self.installationAPI,
            method: "upgrade",
            parameters: [
                "name": .string(update.packageID),
                "is_syno": .boolean(true),
                "beta": .boolean(update.isBeta),
                "url": .string(update.downloadURL.absoluteString),
                "checksum": .string(update.checksum),
                "filesize": .integer(update.fileSize),
                "type": .integer(update.packageType),
                "blqinst": .boolean(false),
                "operation": .string("upgrade"),
            ],
            as: PackageInstallTask.self
        )

        for statusIndex in 0..<updatePollLimit {
            try Task.checkCancellation()
            let status = try await transport.read(
                api: Self.installationAPI,
                method: "status",
                parameters: ["task_id": .string(task.taskID)],
                as: PackageInstallStatus.self
            )
            progress(
                PackageOperationProgress(
                    taskID: task.taskID,
                    statusChecks: statusIndex + 1,
                    isFinished: status.isFinished
                )
            )
            if status.isFinished { return }
            try await Task.sleep(for: updatePollInterval)
        }
        throw DSMError.network(String(localized: "La mise à jour a expiré."))
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
        try await transport.read(
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

    private func packageUpdate(from package: ServerPackage) -> PackageUpdate? {
        let packageType = package.type ?? 0
        let source = package.source?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source?.lowercased() == "syno",
              let packageID = package.id?.trimmingCharacters(in: .whitespacesAndNewlines),
              !packageID.isEmpty,
              let version = package.version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty,
              let link = package.link,
              let downloadURL = URL(string: link),
              downloadURL.scheme?.lowercased() == "https",
              downloadURL.host != nil,
              let rawChecksum = package.md5?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.isValidChecksum(rawChecksum),
              let fileSize = package.size,
              fileSize > 0,
              packageType >= 0 else { return nil }

        return PackageUpdate(
            packageID: packageID,
            version: version,
            downloadURL: downloadURL,
            checksum: rawChecksum.lowercased(),
            fileSize: fileSize,
            isBeta: package.beta ?? false,
            packageType: packageType
        )
    }

    private static func isValidChecksum(_ checksum: String) -> Bool {
        let bytes = checksum.utf8
        guard bytes.count == 32 else { return false }
        return bytes.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }
}
