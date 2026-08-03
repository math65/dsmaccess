//
//  PackagesViewModel.swift
//  dsmaccess
//
//  Loads and administers the packages installed on DSM.
//

import Foundation
import Observation

@MainActor
@Observable
final class PackagesViewModel {
    private(set) var packages: [PackageInfo] = []
    private(set) var catalog: [PackageUpdate] = []
    private(set) var availableUpdates: [String: PackageUpdate] = [:]
    private(set) var capabilities: PackageCenterCapabilities?
    private(set) var isLoading = false
    private(set) var operationProgress: PackageOperationProgress?
    private(set) var transferProgress: DSMTransferProgress?
    private(set) var activeOperationName: String?
    var errorMessage: String?
    var catalogErrorMessage: String?
    private(set) var busy: Set<String> = []

    private let session: SessionStore
    private var loadGeneration = 0
    /// Installed packages and their running state at the end of the previous load, used to
    /// notice that the set of APIs DSM publishes has changed. Nil until the first load, so
    /// the inventory read at sign-in is not immediately read again.
    private var lastKnownPackageStates: [String: Bool]?

    init(session: SessionStore) {
        self.session = session
    }

    func load(forceCatalogRefresh: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        catalogErrorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { client in
                let capabilities = try await client.packageCenterCapabilities()
                guard capabilities.canListInstalledPackages else {
                    throw DSMError.unsupportedAPI("SYNO.Core.Package")
                }
                let packages = try await client.listPackages().sorted {
                    $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                guard capabilities.canBrowseCatalog else {
                    return (packages, [PackageUpdate](), capabilities, String?.none)
                }
                do {
                    let catalog = try await client.officialPackageCatalog(
                        forceRefresh: forceCatalogRefresh
                    )
                    return (packages, catalog, capabilities, String?.none)
                } catch DSMError.sessionExpired {
                    throw DSMError.sessionExpired
                } catch {
                    return (
                        packages,
                        [PackageUpdate](),
                        capabilities,
                        Self.errorDescription(for: error)
                    )
                }
            }
            guard generation == loadGeneration else { return }
            packages = result.0
            catalog = result.1
            capabilities = result.2
            catalogErrorMessage = result.3
            availableUpdates = catalog.reduce(into: [:]) { updates, candidate in
                let key = candidate.packageID.lowercased()
                guard let existing = updates[key] else {
                    updates[key] = candidate
                    return
                }
                if Self.isVersion(candidate.version, newerThan: existing.version) {
                    updates[key] = candidate
                }
            }
            await refreshModuleAvailabilityIfPackagesChanged()
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = Self.errorDescription(for: error)
        }
    }

    /// A package that appears, disappears, starts or stops changes the set of APIs DSM
    /// publishes, and with it the modules the app can offer. Reading the inventory again here
    /// is what lets a module appear without signing in again — including after an install
    /// performed in DSM itself, since a refresh of this screen is enough to notice it.
    ///
    /// A failure leaves the previous inventory in place: the package operation itself
    /// succeeded, and the unavailable-module screen offers an explicit retry.
    private func refreshModuleAvailabilityIfPackagesChanged() async {
        let states = Dictionary(
            packages.map { ($0.pkgId, $0.isRunning) },
            uniquingKeysWith: { first, _ in first }
        )
        defer { lastKnownPackageStates = states }
        guard let previous = lastKnownPackageStates, previous != states else { return }
        do {
            try await session.refreshCapabilities()
        } catch {
            // Keeping the inventory read at sign-in is the previous behaviour, not a new failure.
        }
    }

    func setRunning(_ package: PackageInfo, running: Bool) async -> DSMOperationOutcome {
        guard capabilities?.canControlPackages == true, package.canStartStop else {
            return .failure(
                String(localized: "packages.control.unavailable.error")
            )
        }
        let id = package.pkgId
        guard busy.insert(id).inserted else {
            return .failure(String(localized: "packages.operation.busy_package.error"))
        }
        defer { busy.remove(id) }
        do {
            try await session.withClient { try await $0.setPackageRunning(id: id, running: running) }
            await load()
            return .success(
                running
                    ? String(localized: "packages.start.success", defaultValue: "\(package.displayName) started")
                    : String(localized: "packages.stop.success", defaultValue: "\(package.displayName) stopped")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            await load()
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(package.displayName): \(reason)"))
        }
    }

    func uninstall(_ package: PackageInfo) async -> DSMOperationOutcome {
        guard capabilities?.canUninstallPackages == true, package.canUninstall else {
            return .failure(
                String(localized: "packages.uninstall.unavailable.error")
            )
        }
        guard !package.hasUninstallOptions else {
            return .failure(
                String(
                    localized: "packages.uninstall.assistant_required.error"
                )
            )
        }
        let id = package.pkgId
        guard busy.insert(id).inserted else {
            return .failure(String(localized: "packages.operation.busy_package.error"))
        }
        defer { busy.remove(id) }
        do {
            try await session.withClient { try await $0.uninstallPackage(id: id) }
            await load()
            return .success(String(localized: "packages.uninstall.success", defaultValue: "\(package.displayName) uninstalled"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            await load()
            return .failure(
                String(localized: "packages.uninstall.error", defaultValue: "Failed to uninstall \(package.displayName): \(reason)")
            )
        }
    }

    func applyUpdate(_ package: PackageInfo) async -> DSMOperationOutcome {
        guard capabilities?.canInstallVerifiedUpdates == true else {
            return .failure(
                String(localized: "packages.update.unavailable.error")
            )
        }
        guard let update = update(for: package) else {
            return .failure(
                String(localized: "packages.update.none_for_package.error", defaultValue: "No update is available for \(package.displayName).")
            )
        }

        let id = package.pkgId
        guard busy.insert(id).inserted else {
            return .failure(String(localized: "packages.operation.busy_package.error"))
        }
        activeOperationName = String(localized: "packages.update.status", defaultValue: "Updating \(package.displayName)")
        operationProgress = nil
        defer {
            busy.remove(id)
            activeOperationName = nil
            operationProgress = nil
        }
        do {
            try await session.withClient {
                try await $0.upgradePackage(
                    update,
                    progress: { [weak self] progress in
                        self?.operationProgress = progress
                    }
                )
            }
            await load(forceCatalogRefresh: true)
            return .success(String(localized: "packages.update.success", defaultValue: "\(package.displayName) updated"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = Self.errorDescription(for: error)
            await load()
            return .failure(
                String(localized: "packages.update.error", defaultValue: "Failed to update \(package.displayName): \(reason)")
            )
        }
    }

    func install(_ catalogItem: PackageUpdate) async -> DSMOperationOutcome {
        guard capabilities?.canInstallCatalogPackages == true else {
            return .failure(
                String(localized: "common.error.catalog_install_unavailable")
            )
        }
        guard installedPackage(for: catalogItem) == nil else {
            return .failure(
                String(localized: "packages.install.already_installed.error", defaultValue: "The \(catalogItem.packageID) package is already installed.")
            )
        }
        guard !catalogItem.requirements.requiresInteractiveInstaller else {
            return .failure(
                String(
                    localized: "common.error.package_requires_dsm_wizard",
                    defaultValue: "The \(catalogItem.packageID) package requires a DSM licence or configuration wizard. Install it in DSM Package Center so you can make those choices explicitly."
                )
            )
        }
        return await runCatalogOperation(
            packageID: catalogItem.packageID,
            operationName: String(localized: "packages.install.status", defaultValue: "Installing \(catalogItem.packageID)"),
            successMessage: String(localized: "packages.install.success", defaultValue: "\(catalogItem.packageID) installed")
        ) { client, progress in
            try await client.installPackage(catalogItem, progress: progress)
        }
    }

    func repair(_ package: PackageInfo) async -> DSMOperationOutcome {
        guard capabilities?.canRepairPackages == true, package.requiresAttention else {
            return .failure(
                String(localized: "packages.repair.unavailable.error")
            )
        }
        guard let catalogItem = catalogItem(for: package) else {
            return .failure(
                String(
                    localized: "packages.repair.no_official_package.error",
                    defaultValue: "No matching official package is available to repair \(package.displayName)."
                )
            )
        }
        guard !catalogItem.requirements.requiresInteractiveInstaller else {
            return .failure(
                String(
                    localized: "packages.repair.assistant_required.error",
                    defaultValue: "The \(package.displayName) package requires a DSM licence or configuration wizard. Repair it in DSM Package Center so you can make those choices explicitly."
                )
            )
        }
        let installsNewerVersion = update(for: package) != nil
        return await runCatalogOperation(
            packageID: package.pkgId,
            operationName: String(localized: "packages.repair.status", defaultValue: "Repairing \(package.displayName)"),
            successMessage: installsNewerVersion
                ? String(localized: "packages.repair.updated.success", defaultValue: "\(package.displayName) repaired and updated")
                : String(localized: "packages.repair.success", defaultValue: "\(package.displayName) repaired")
        ) { client, progress in
            try await client.repairPackage(
                catalogItem,
                installsNewerVersion: installsNewerVersion,
                progress: progress
            )
        }
    }

    func installManualPackage(at fileURL: URL) async -> DSMOperationOutcome {
        guard capabilities?.canInstallManualPackages == true else {
            return .failure(
                String(localized: "packages.manual_install.unavailable.error")
            )
        }
        let filename = fileURL.lastPathComponent
        let operationID = "manual:\(filename.lowercased())"
        guard busy.insert(operationID).inserted else {
            return .failure(String(localized: "packages.manual_install.busy.error"))
        }
        activeOperationName = String(localized: "packages.install.status", defaultValue: "Installing \(filename)")
        operationProgress = nil
        transferProgress = nil
        let hasSecurityScope = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope { fileURL.stopAccessingSecurityScopedResource() }
            busy.remove(operationID)
            activeOperationName = nil
            operationProgress = nil
            transferProgress = nil
        }
        do {
            let installedName = try await session.withClient {
                try await $0.installManualPackage(
                    at: fileURL,
                    progress: { [weak self] progress in
                        self?.transferProgress = progress
                    }
                )
            }
            await load(forceCatalogRefresh: true)
            return .success(String(localized: "packages.install.success", defaultValue: "\(installedName) installed"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = Self.errorDescription(for: error)
            await load()
            return .failure(
                String(localized: "packages.install.error", defaultValue: "Failed to install \(filename): \(reason)")
            )
        }
    }

    func applyAllUpdates() async -> DSMOperationOutcome {
        guard capabilities?.canInstallVerifiedUpdates == true else {
            return .failure(
                String(localized: "packages.update.unavailable.error")
            )
        }
        let updates = packages.compactMap { package in
            update(for: package).map { (package, $0) }
        }
        guard !updates.isEmpty else {
            return .failure(String(localized: "packages.update.none.error"))
        }
        let identifiers = Set(updates.map { $0.0.pkgId })
        guard busy.isDisjoint(with: identifiers) else {
            return .failure(String(localized: "packages.operation.busy.error"))
        }
        busy.formUnion(identifiers)
        operationProgress = nil
        defer {
            busy.subtract(identifiers)
            activeOperationName = nil
            operationProgress = nil
        }

        var completed = 0
        var failures = [String]()
        for (package, update) in updates {
            do {
                try Task.checkCancellation()
                activeOperationName = String(localized: "packages.update.status", defaultValue: "Updating \(package.displayName)")
                operationProgress = nil
                try await session.withClient {
                    try await $0.upgradePackage(
                        update,
                        progress: { [weak self] progress in
                            self?.operationProgress = progress
                        }
                    )
                }
                completed += 1
            } catch where DSMError.isCancellation(error) {
                return .cancelled
            } catch {
                failures.append(
                    String(
                        localized: "packages.operation.detail.format",
                        defaultValue: "\(package.displayName): \(Self.errorDescription(for: error))"
                    )
                )
            }
        }
        await load(forceCatalogRefresh: true)
        if failures.isEmpty {
            return .success(String(localized: "packages.update_all.success", defaultValue: "\(completed) packages updated"))
        }
        let failureSummary = failures.formatted(.list(type: .and))
        return .failure(
            String(
                localized: "packages.update_all.partial_failure.summary",
                defaultValue: "\(completed) packages updated, \(failures.count) failed: \(failureSummary)"
            )
        )
    }

    func updateVersion(for package: PackageInfo) -> String? {
        update(for: package)?.version
    }

    func update(for package: PackageInfo) -> PackageUpdate? {
        let id = package.pkgId.lowercased()
        guard let candidate = availableUpdates[id],
              let installed = package.version,
              Self.isVersion(candidate.version, newerThan: installed) else { return nil }
        return candidate
    }

    func installedPackage(for catalogItem: PackageUpdate) -> PackageInfo? {
        packages.first { $0.pkgId.caseInsensitiveCompare(catalogItem.packageID) == .orderedSame }
    }

    func catalogItem(for package: PackageInfo) -> PackageUpdate? {
        catalog.first {
            $0.packageID.caseInsensitiveCompare(package.pkgId) == .orderedSame
        }
    }

    func canInstall(_ catalogItem: PackageUpdate) -> Bool {
        capabilities?.canInstallCatalogPackages == true
            && installedPackage(for: catalogItem) == nil
            && !catalogItem.requirements.requiresInteractiveInstaller
    }

    func canRepair(_ package: PackageInfo) -> Bool {
        capabilities?.canRepairPackages == true
            && package.requiresAttention
            && catalogItem(for: package)?.requirements.requiresInteractiveInstaller == false
    }

    func canSafelyUninstall(_ package: PackageInfo) -> Bool {
        capabilities?.canUninstallPackages == true
            && package.canUninstall
            && !package.hasUninstallOptions
    }

    var canApplyUpdates: Bool {
        capabilities?.canInstallVerifiedUpdates == true
    }

    var canBrowseCatalog: Bool {
        capabilities?.canBrowseCatalog == true
    }

    var operationStatusText: String? {
        guard let activeOperationName else { return nil }
        if let transferProgress {
            if let fraction = transferProgress.fractionCompleted, fraction < 1 {
                return String(
                    localized: "packages.operation.upload.progress",
                    defaultValue: "\(activeOperationName), upload \(fraction.formatted(.percent.precision(.fractionLength(0))))"
                )
            }
            return String(localized: "packages.operation.installing.progress", defaultValue: "\(activeOperationName), installing on the NAS")
        }
        guard let operationProgress else {
            return String(localized: "packages.operation.preparing.progress", defaultValue: "\(activeOperationName), preparing on the NAS")
        }
        return String(
            localized: "packages.operation.status_check.progress",
            defaultValue: "\(activeOperationName), status check \(operationProgress.statusChecks)"
        )
    }

    private func runCatalogOperation(
        packageID: String,
        operationName: String,
        successMessage: String,
        operation: (
            DSMClientProtocol,
            @escaping @MainActor (PackageOperationProgress) -> Void
        ) async throws -> Void
    ) async -> DSMOperationOutcome {
        guard busy.insert(packageID).inserted else {
            return .failure(String(localized: "packages.operation.busy_package.error"))
        }
        activeOperationName = operationName
        operationProgress = nil
        transferProgress = nil
        defer {
            busy.remove(packageID)
            activeOperationName = nil
            operationProgress = nil
            transferProgress = nil
        }
        do {
            try await session.withClient { client in
                try await operation(client) { [weak self] progress in
                    self?.operationProgress = progress
                }
            }
            await load(forceCatalogRefresh: true)
            return .success(successMessage)
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = Self.errorDescription(for: error)
            await load()
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(packageID): \(reason)"))
        }
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        compareVersion(candidate, with: current) == .orderedDescending
    }

    private enum VersionToken: Equatable {
        case number(String)
        case word(String)
    }

    private static func compareVersion(_ left: String, with right: String) -> ComparisonResult {
        let leftTokens = versionTokens(left)
        let rightTokens = versionTokens(right)
        let commonCount = min(leftTokens.count, rightTokens.count)
        for index in 0..<commonCount {
            let result = compare(leftTokens[index], with: rightTokens[index])
            if result != .orderedSame { return result }
        }
        if leftTokens.count == rightTokens.count { return .orderedSame }
        if leftTokens.count > commonCount {
            return comparisonResult(forRemainder: leftTokens[commonCount...])
        }
        let result = comparisonResult(forRemainder: rightTokens[commonCount...])
        return switch result {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }

    private static func versionTokens(_ version: String) -> [VersionToken] {
        enum TokenKind {
            case number
            case word
        }

        var tokens = [VersionToken]()
        var current = ""
        var currentKind: TokenKind?

        func appendCurrent() {
            guard let currentKind, !current.isEmpty else { return }
            switch currentKind {
            case .number:
                tokens.append(.number(current))
            case .word:
                tokens.append(.word(current.lowercased()))
            }
            current = ""
        }

        for character in version {
            let kind: TokenKind? = if character.isNumber {
                .number
            } else if character.isLetter {
                .word
            } else {
                nil
            }
            guard let kind else {
                appendCurrent()
                currentKind = nil
                continue
            }
            if let currentKind, currentKind != kind {
                appendCurrent()
            }
            currentKind = kind
            current.append(character)
        }
        appendCurrent()
        return tokens
    }

    private static func compare(_ left: VersionToken, with right: VersionToken) -> ComparisonResult {
        switch (left, right) {
        case (.number(let left), .number(let right)):
            return compareNumericStrings(left, right)
        case (.word(let left), .word(let right)):
            let leftRank = qualifierRank(left)
            let rightRank = qualifierRank(right)
            if leftRank != rightRank {
                return leftRank < rightRank ? .orderedAscending : .orderedDescending
            }
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case (.number, .word(let word)):
            return qualifierRank(word) < 0 ? .orderedDescending : .orderedAscending
        case (.word(let word), .number):
            return qualifierRank(word) < 0 ? .orderedAscending : .orderedDescending
        }
    }

    private static func compareNumericStrings(
        _ left: String,
        _ right: String
    ) -> ComparisonResult {
        let normalizedLeft = String(left.drop(while: { $0 == "0" }))
        let normalizedRight = String(right.drop(while: { $0 == "0" }))
        let significantLeft = normalizedLeft.isEmpty ? "0" : normalizedLeft
        let significantRight = normalizedRight.isEmpty ? "0" : normalizedRight
        if significantLeft.count != significantRight.count {
            return significantLeft.count < significantRight.count
                ? .orderedAscending
                : .orderedDescending
        }
        if significantLeft == significantRight { return .orderedSame }
        return significantLeft < significantRight ? .orderedAscending : .orderedDescending
    }

    private static func comparisonResult(
        forRemainder remainder: ArraySlice<VersionToken>
    ) -> ComparisonResult {
        for token in remainder {
            switch token {
            case .number(let value):
                if compareNumericStrings(value, "0") == .orderedDescending {
                    return .orderedDescending
                }
            case .word(let value):
                return qualifierRank(value) < 0 ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private static func qualifierRank(_ value: String) -> Int {
        switch value {
        case "alpha", "a": -4
        case "beta", "b", "preview", "pre": -3
        case "rc": -2
        default: 1
        }
    }

    private static func errorDescription(for error: Error) -> String {
        (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }

    var updateCount: Int {
        packages.filter { updateVersion(for: $0) != nil }.count
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let base: String
        if !availableUpdates.isEmpty && updateCount > 0 {
            base = String(
                localized: "packages.summary.count_with_updates",
                defaultValue: "\(packages.count) packages, \(updateCount) updates available"
            )
        } else {
            base = String(localized: "packages.installed.count", defaultValue: "\(packages.count) installed packages")
        }
        if let catalogErrorMessage {
            return String(
                localized: "packages.catalog.unavailable.summary",
                defaultValue: "\(base). Catalog unavailable: \(catalogErrorMessage)"
            )
        }
        return base
    }
}
