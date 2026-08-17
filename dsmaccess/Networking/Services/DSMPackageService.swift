//
//  DSMPackageService.swift
//  dsmaccess
//
//  Management of installed packages, the catalogue and the global settings.
//

import Foundation

@MainActor
final class DSMPackageService {
    private static let packageAPI = DSMAPI("SYNO.Core.Package")
    private static let serverAPI = DSMAPI("SYNO.Core.Package.Server")
    private static let controlAPI = DSMAPI("SYNO.Core.Package.Control")
    private static let uninstallationAPI = DSMAPI("SYNO.Core.Package.Uninstallation")
    private static let settingAPI = DSMAPI("SYNO.Core.Package.Setting")
    private static let feedAPI = DSMAPI("SYNO.Core.Package.Feed", preferredVersion: 1)
    private static let installationAPI = DSMAPI(
        "SYNO.Core.Package.Installation",
        preferredVersion: 1
    )
    private static let installationDownloadAPI = DSMAPI(
        "SYNO.Core.Package.Installation.Download",
        preferredVersion: 1
    )
    private static let entryRequestAPI = DSMAPI("SYNO.Entry.Request", preferredVersion: 1)

    private enum CatalogOperation {
        case install
        case upgrade
        case repair(installsNewerVersion: Bool)

        var method: String {
            switch self {
            case .install: "install"
            case .upgrade, .repair: "upgrade"
            }
        }

        var downloadOperation: String {
            switch self {
            case .upgrade, .repair(installsNewerVersion: true): "upgrade"
            case .install, .repair(installsNewerVersion: false): "install"
            }
        }

        var isUpgrade: Bool { downloadOperation == "upgrade" }
    }

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
            Self.feedAPI,
            Self.installationDownloadAPI,
            Self.entryRequestAPI,
        ]
        let maximumVersions = Dictionary(
            uniqueKeysWithValues: apis.compactMap { api in
                transport.capabilities.entry(for: api.name).map { (api.name, $0.maxVersion) }
            }
        )
        let hasInstallationPipeline = transport.capabilities.supports(Self.packageAPI)
            && transport.capabilities.supports(Self.installationAPI)
            && transport.capabilities.supports(Self.installationDownloadAPI)
            && transport.capabilities.supports(Self.entryRequestAPI)
        return PackageCenterCapabilities(
            canListInstalledPackages: transport.capabilities.supports(Self.packageAPI),
            canBrowseCatalog: transport.capabilities.supports(Self.serverAPI),
            canInstallCatalogPackages: hasInstallationPipeline
                && transport.capabilities.supports(Self.serverAPI),
            canInstallManualPackages: transport.capabilities.supports(Self.packageAPI)
                && transport.capabilities.supports(Self.installationAPI)
                && transport.capabilities.supports(Self.entryRequestAPI),
            canInstallVerifiedUpdates: hasInstallationPipeline
                && transport.capabilities.supports(Self.serverAPI),
            canRepairPackages: hasInstallationPipeline
                && transport.capabilities.supports(Self.serverAPI),
            canControlPackages: transport.capabilities.supports(Self.controlAPI),
            canUninstallPackages: transport.capabilities.supports(Self.uninstallationAPI),
            canManageSettings: transport.capabilities.supports(Self.settingAPI),
            canManagePackageSources: transport.capabilities.supports(Self.feedAPI),
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
                    "dsm_apps",
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
        try await runCatalogOperation(.upgrade, update: update, progress: progress)
    }

    func install(_ update: PackageUpdate) async throws {
        try await install(update, progress: { _ in })
    }

    func install(
        _ update: PackageUpdate,
        progress: (PackageOperationProgress) -> Void
    ) async throws {
        try await runCatalogOperation(.install, update: update, progress: progress)
    }

    func repair(
        _ update: PackageUpdate,
        installsNewerVersion: Bool,
        progress: (PackageOperationProgress) -> Void
    ) async throws {
        try await runCatalogOperation(
            .repair(installsNewerVersion: installsNewerVersion),
            update: update,
            progress: progress
        )
    }

    func installManualPackage(
        at fileURL: URL,
        progress: @escaping DSMTransferProgressHandler = { _ in }
    ) async throws -> String {
        guard fileURL.isFileURL,
              fileURL.pathExtension.caseInsensitiveCompare("spk") == .orderedSame,
              try await MultipartBodyFile.fileSize(at: fileURL) > 0 else {
            throw DSMError.packageCenter(
                String(localized: "packages.install.invalid_spk.error")
            )
        }

        let metadata = try await uploadManualPackage(at: fileURL, progress: progress)
        guard let taskID = metadata.taskID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !taskID.isEmpty else {
            throw DSMError.invalidResponse
        }

        do {
            guard !metadata.requiresInteractiveInstaller else {
                throw DSMError.packageCenter(
                    String(
                        localized: "common.error.package_requires_dsm_wizard",
                        defaultValue: "The \(metadata.displayName) package requires a DSM licence or configuration wizard. Install it in DSM Package Center so you can make those choices explicitly."
                    )
                )
            }
            try await feasibilityCheck(packageID: metadata.packageID, type: "install_check")
            // check_codesign is false here: that is what the web client sends once the
            // "third-party package" warning has been accepted, which the app does through its
            // own confirmation before sending the file.
            try await finalizeInstallation(
                metadata: metadata,
                method: metadata.isAlreadyInstalled ? "upgrade" : "install",
                packageType: 0,
                checkDependencies: true,
                checkCodesign: false,
                force: false,
                source: .task(taskID)
            )
            // DSM may delete the task as soon as the installation finishes.
            try? await cleanUploadedPackage(taskID: taskID)
            return metadata.displayName
        } catch {
            // After a rejected check or installation, DSM may already have deleted the task.
            // A failure of this fallback cleanup must not hide the useful error.
            try? await cleanUploadedPackage(taskID: taskID)
            throw error
        }
    }

    func packageSources() async throws -> [PackageSource] {
        let list = try await transport.read(
            api: Self.feedAPI,
            method: "list",
            as: PackageSourceList.self
        )
        return list.items
    }

    func addPackageSource(_ source: PackageSource) async throws {
        try await setPackageSource(source, originalFeed: nil)
    }

    func updatePackageSource(_ source: PackageSource, originalFeed: String) async throws {
        try await setPackageSource(source, originalFeed: originalFeed)
    }

    func deletePackageSources(feeds: [String]) async throws {
        let normalized = feeds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !normalized.isEmpty, normalized.allSatisfy({ !$0.isEmpty }) else {
            throw DSMError.invalidResponse
        }
        try await transport.perform(
            api: Self.feedAPI,
            method: "delete",
            parameters: ["list": try DSMParameter.json(normalized)]
        )
    }

    private func runCatalogOperation(
        _ operation: CatalogOperation,
        update: PackageUpdate,
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
        guard !update.requirements.requiresInteractiveInstaller else {
            throw DSMError.packageCenter(
                String(
                    localized: "common.error.package_requires_dsm_wizard",
                    defaultValue: "The \(update.packageID) package requires a DSM licence or configuration wizard. Install it in DSM Package Center so you can make those choices explicitly."
                )
            )
        }

        try await feasibilityCheck(packageID: update.packageID, type: "install_check")
        let queue = try await transport.read(
            api: Self.installationAPI,
            method: "get_queue",
            parameters: [
                "pkgs": try DSMParameter.json([
                    PackageInstallQueueRequest(
                        packageID: update.packageID,
                        operation: "install",
                        version: update.version,
                        isBeta: update.isBeta
                    )
                ])
            ],
            as: PackageInstallQueue.self
        )
        try validate(queue: queue, packageID: update.packageID)

        _ = try await transport.read(
            api: DSMAPI(Self.installationAPI.name, preferredVersion: 2),
            method: "check",
            parameters: try environmentCheckParameters(update, operation: operation),
            as: EmptyData.self
        )

        let task = try await transport.value(
            api: Self.installationAPI,
            method: operation.method,
            parameters: [
                "name": .string(update.packageID),
                "is_syno": .boolean(true),
                "beta": .boolean(update.isBeta),
                "url": .string(update.downloadURL.absoluteString),
                "checksum": .string(update.checksum),
                "filesize": .integer(update.fileSize),
                "type": .integer(update.packageType),
                "blqinst": .boolean(false),
                "operation": .string(operation.downloadOperation),
            ],
            timeoutInterval: 900,
            as: PackageInstallTask.self
        )

        try await waitForDownload(taskID: task.taskID, progress: progress)
        let metadata = try await transport.read(
            api: Self.installationDownloadAPI,
            method: "check",
            parameters: [
                "taskid": .string("@SYNOPKG_DOWNLOAD_\(update.packageID)"),
            ],
            timeoutInterval: 900,
            as: PackageInstallationMetadata.self
        )
        guard metadata.packageID.caseInsensitiveCompare(update.packageID) == .orderedSame,
              let filename = metadata.filename?.trimmingCharacters(in: .whitespacesAndNewlines),
              !filename.isEmpty else {
            throw DSMError.invalidResponse
        }

        do {
            try await finalizeInstallation(
                metadata: metadata,
                method: operation.method,
                packageType: update.packageType,
                checkDependencies: false,
                checkCodesign: true,
                force: true,
                source: .path(filename)
            )
        } catch {
            try? await deleteDownloadedPackage(at: filename)
            throw error
        }
        // DSM may already have deleted the artefact once the installation is done.
        try? await deleteDownloadedPackage(at: filename)
    }

    func setRunning(_ running: Bool, packageID: String) async throws {
        try await transport.perform(
            api: Self.controlAPI,
            method: running ? "start" : "stop",
            parameters: ["id": .string(packageID)],
            timeoutInterval: 900
        )
    }

    /// `dsm_apps` carries the space-separated DSM application identifiers the package
    /// installed on the desktop, exactly as the list returned them. The web client passes
    /// them back so DSM removes the desktop entries along with the package; sending an empty
    /// value left them behind.
    func uninstall(packageID: String, dsmApps: String) async throws {
        try await transport.perform(
            api: Self.uninstallationAPI,
            method: "uninstall",
            parameters: [
                "id": .string(packageID),
                "dsm_apps": .string(dsmApps),
            ],
            timeoutInterval: 900
        )
    }

    func settings() async throws -> PackageSettings {
        try await transport.read(
            api: Self.settingAPI,
            method: "get",
            as: PackageSettings.self
        )
    }

    /// Sends exactly the six fields the Package Center web client sends. DSM neither returns
    /// `default_vol` here nor expects it back, and it leaves `trust_level` alone.
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
            packageType: packageType,
            requirements: PackageInstallationRequirements(
                dependencyServers: package.dependencyServers,
                dependencyPackages: package.dependencyPackages,
                conflictingPackages: package.conflictingPackages,
                breakingPackages: package.breakingPackages,
                replacementPackages: package.replacementPackages,
                installType: package.installType ?? "",
                installOnColdStorage: package.installOnColdStorage,
                hasLicenseAgreement: package.license?.hasContent == true,
                hasCustomInstallPages: package.installPages?.hasContent == true
            )
        )
    }

    private enum InstallationSource {
        case path(String)
        case task(String)
    }

    private struct PackageInstallQueueRequest: Encodable {
        let pkg: String
        let operation: String
        let version: String
        let beta: Bool

        init(packageID: String, operation: String, version: String, isBeta: Bool) {
            pkg = packageID
            self.operation = operation
            self.version = version
            beta = isBeta
        }
    }

    private func feasibilityCheck(packageID: String, type: String) async throws {
        let response = try await transport.response(
            api: DSMAPI(Self.packageAPI.name, preferredVersion: 1),
            method: "feasibility_check",
            parameters: [
                "type": .string(type),
                "packages": try DSMParameter.json([packageID]),
            ],
            requestPolicy: .idempotent,
            as: EmptyData.self
        )
        guard response.success else {
            throw transport.error(from: response.error)
        }
    }

    private func validate(queue: PackageInstallQueue, packageID: String) throws {
        let queuedTarget = queue.queue.count == 1
            && queue.queue[0].packageID.caseInsensitiveCompare(packageID) == .orderedSame
            && (queue.queue[0].operation ?? "install") == "install"
        guard queue.brokenPackages.isEmpty,
              queue.conflictingPackages.isEmpty,
              queue.missingPackages.isEmpty,
              queue.pausedPackages.isEmpty,
              queue.replacementPackages.isEmpty,
              queuedTarget else {
            throw DSMError.packageCenter(
                String(
                    localized: "packages.install.extra_operations.error"
                )
            )
        }
    }

    private func environmentCheckParameters(
        _ update: PackageUpdate,
        operation: CatalogOperation
    ) throws -> [String: DSMParameter] {
        let requirements = update.requirements
        return [
            "depsers": try DSMParameter.json(requirements.dependencyServers ?? .string("")),
            "deppkgs": try DSMParameter.json(requirements.dependencyPackages ?? .null),
            "conflictpkgs": try DSMParameter.json(requirements.conflictingPackages ?? .null),
            "breakpkgs": try DSMParameter.json(requirements.breakingPackages ?? .null),
            "replacepkgs": try DSMParameter.json(requirements.replacementPackages ?? .null),
            "ver": .string(update.version),
            "size": .integer(update.fileSize),
            "id": .string(update.packageID),
            "blupgrade": .boolean(operation.isUpgrade),
            "install_type": .string(requirements.installType),
            "install_on_cold_storage": try DSMParameter.json(
                requirements.installOnColdStorage ?? .string("")
            ),
            "blCheckDep": .boolean(false),
        ]
    }

    private func waitForDownload(
        taskID: String,
        progress: (PackageOperationProgress) -> Void
    ) async throws {
        for statusIndex in 0..<updatePollLimit {
            try Task.checkCancellation()
            let status = try await transport.read(
                api: Self.installationAPI,
                method: "status",
                parameters: ["task_id": .string(taskID)],
                as: PackageInstallStatus.self
            )
            progress(
                PackageOperationProgress(
                    taskID: taskID,
                    statusChecks: statusIndex + 1,
                    isFinished: status.isFinished
                )
            )
            if status.isFinished {
                guard status.wasSuccessful != false else {
                    throw DSMError.packageCenter(
                        String(localized: "packages.install.download_failed.error")
                    )
                }
                return
            }
            try await Task.sleep(for: updatePollInterval)
        }
        throw DSMError.network(String(localized: "packages.install.timeout.error"))
    }

    private func finalizeInstallation(
        metadata: PackageInstallationMetadata,
        method: String,
        packageType: Int,
        checkDependencies: Bool,
        checkCodesign: Bool,
        force: Bool,
        source: InstallationSource
    ) async throws {
        let check: [String: DSMJSONValue] = [
            "api": .string(Self.installationAPI.name),
            "method": .string("check"),
            "version": .integer(2),
            "id": .string(metadata.packageID),
            "install_type": .string(metadata.installType),
            "install_on_cold_storage": .boolean(metadata.installOnColdStorage),
            "breakpkgs": metadata.breakingPackages ?? .null,
            "blCheckDep": .boolean(checkDependencies),
            "replacepkgs": metadata.replacementPackages ?? .null,
        ]
        var install: [String: DSMJSONValue] = [
            "api": .string(Self.installationAPI.name),
            "method": .string(method),
            "version": .integer(1),
            // DSM 7.4 (90075) rejects a JSON object here (code 120): the value must be the
            // string "{}", as the Package Center web client sends it.
            "extra_values": .string("{}"),
            "type": .integer(packageType),
            "check_codesign": .boolean(checkCodesign),
            "force": .boolean(force),
            "installrunpackage": .boolean(true),
        ]
        switch source {
        case .path(let path):
            install["path"] = .string(path)
        case .task(let taskID):
            install["task_id"] = .string(taskID)
        }
        let refresh: [String: DSMJSONValue] = [
            "api": .string(Self.packageAPI.name),
            "method": .string("get"),
            "version": .integer(1),
            "id": .string(metadata.packageID),
            "additional": .array([.string("status"), .string("dsm_apps")]),
        ]
        let result = try await transport.value(
            api: Self.entryRequestAPI,
            method: "request",
            parameters: [
                "stop_when_error": .boolean(true),
                "mode": .string("sequential"),
                "compound": try DSMParameter.json([check, install, refresh]),
            ],
            timeoutInterval: 900,
            as: PackageCompoundData.self
        )
        guard !result.hasFailure,
              result.results.count == 3,
              result.results.allSatisfy(\.success) else {
            if let error = result.results.first(where: { !$0.success })?.error {
                throw transport.error(from: error)
            }
            throw DSMError.invalidResponse
        }
    }

    private func uploadManualPackage(
        at fileURL: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws -> PackageInstallationMetadata {
        let boundary = "Boundary-\(UUID().uuidString)"
        // DSM 7.4 contract (captured from the Package Center web client): api, method,
        // version and session go in the URL query — placed in the multipart body, DSM
        // answers 101. The body carries only "additional" then the file.
        let route = try await transport.multipartRoute(
            api: Self.installationAPI,
            method: "upload",
            parameters: [
                "additional": try DSMParameter.json([
                    "description", "maintainer", "distributor", "startable", "dsm_apps",
                    "status", "install_reboot", "install_type", "install_on_cold_storage",
                    "break_pkgs", "replace_pkgs",
                ])
            ]
        )
        var query = route.fields
        let additional = query.removeValue(forKey: "additional")
        let resolved = try await transport.resolvedAPI(Self.installationAPI)
        let uploadURL = try transport.makeURL(path: resolved.path, parameters: query)
        let bodyURL = try await MultipartBodyFile.create(
            fields: additional.map { ["additional": $0] } ?? [:],
            fileURL: fileURL,
            fileFieldName: "file",
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 900
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        let (data, response) = try await transport.upload(
            for: request,
            fromFile: bodyURL,
            progress: progress
        )
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        let result = try await DSMTransport.decodeResponse(PackageInstallationMetadata.self, from: data)
        guard result.success, let metadata = result.data else {
            throw transport.error(from: result.error)
        }
        return metadata
    }

    private func cleanUploadedPackage(taskID: String) async throws {
        try await transport.perform(
            api: Self.installationAPI,
            method: "clean",
            parameters: ["task_id": .string(taskID)]
        )
    }

    private func deleteDownloadedPackage(at path: String) async throws {
        try await transport.perform(
            api: Self.installationAPI,
            method: "delete",
            parameters: ["path": .string(path)]
        )
    }

    private func setPackageSource(_ source: PackageSource, originalFeed: String?) async throws {
        let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let feed = source.feed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let url = URL(string: feed),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw DSMError.packageCenter(
                String(localized: "common.validation.invalid_package_source")
            )
        }
        var entry = ["name": name, "feed": feed]
        if let originalFeed {
            let normalizedOriginalFeed = originalFeed.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard !normalizedOriginalFeed.isEmpty else { throw DSMError.invalidResponse }
            entry["orifeed"] = normalizedOriginalFeed
        }
        try await transport.perform(
            api: Self.feedAPI,
            method: originalFeed == nil ? "add" : "set",
            parameters: ["list": try DSMParameter.json(entry)]
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
