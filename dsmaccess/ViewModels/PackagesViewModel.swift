//
//  PackagesViewModel.swift
//  dsmaccess
//
//  Charge et administre les paquets installés sur DSM.
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
    private(set) var activeOperationName: String?
    var errorMessage: String?
    var catalogErrorMessage: String?
    private(set) var busy: Set<String> = []

    private let session: SessionStore
    private var loadGeneration = 0

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
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = Self.errorDescription(for: error)
        }
    }

    func setRunning(_ package: PackageInfo, running: Bool) async -> DSMOperationOutcome {
        guard capabilities?.canControlPackages == true, package.canStartStop else {
            return .failure(
                String(localized: "Le contrôle de ce paquet n’est pas disponible sur ce NAS.")
            )
        }
        let id = package.pkgId
        guard busy.insert(id).inserted else {
            return .failure(String(localized: "Une opération est déjà en cours pour ce paquet."))
        }
        defer { busy.remove(id) }
        do {
            try await session.withClient { try await $0.setPackageRunning(id: id, running: running) }
            await load()
            return .success(
                running
                    ? String(localized: "\(package.displayName) démarré")
                    : String(localized: "\(package.displayName) arrêté")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            await load()
            return .failure(String(localized: "Échec pour \(package.displayName) : \(reason)"))
        }
    }

    func uninstall(_ package: PackageInfo) async -> DSMOperationOutcome {
        guard capabilities?.canUninstallPackages == true, package.canUninstall else {
            return .failure(
                String(localized: "La désinstallation de ce paquet n’est pas disponible sur ce NAS.")
            )
        }
        guard !package.hasUninstallOptions else {
            return .failure(
                String(
                    localized: "Ce paquet exige un assistant de désinstallation propre à DSM. Désinstallez-le depuis le Centre de paquets DSM pour choisir correctement le traitement de ses données."
                )
            )
        }
        let id = package.pkgId
        guard busy.insert(id).inserted else {
            return .failure(String(localized: "Une opération est déjà en cours pour ce paquet."))
        }
        defer { busy.remove(id) }
        do {
            try await session.withClient { try await $0.uninstallPackage(id: id) }
            await load()
            return .success(String(localized: "\(package.displayName) désinstallé"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            await load()
            return .failure(
                String(localized: "Échec de la désinstallation de \(package.displayName) : \(reason)")
            )
        }
    }

    func applyUpdate(_ package: PackageInfo) async -> DSMOperationOutcome {
        guard capabilities?.canInstallVerifiedUpdates == true else {
            return .failure(
                String(localized: "L’installation des mises à jour n’est pas disponible sur ce NAS.")
            )
        }
        guard let update = update(for: package) else {
            return .failure(
                String(localized: "Aucune mise à jour disponible pour \(package.displayName).")
            )
        }

        let id = package.pkgId
        guard busy.insert(id).inserted else {
            return .failure(String(localized: "Une opération est déjà en cours pour ce paquet."))
        }
        activeOperationName = String(localized: "Mise à jour de \(package.displayName)")
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
            return .success(String(localized: "\(package.displayName) mis à jour"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = Self.errorDescription(for: error)
            await load()
            return .failure(
                String(localized: "Échec de la mise à jour de \(package.displayName) : \(reason)")
            )
        }
    }

    func applyAllUpdates() async -> DSMOperationOutcome {
        guard capabilities?.canInstallVerifiedUpdates == true else {
            return .failure(
                String(localized: "L’installation des mises à jour n’est pas disponible sur ce NAS.")
            )
        }
        let updates = packages.compactMap { package in
            update(for: package).map { (package, $0) }
        }
        guard !updates.isEmpty else {
            return .failure(String(localized: "Aucune mise à jour disponible."))
        }
        let identifiers = Set(updates.map { $0.0.pkgId })
        guard busy.isDisjoint(with: identifiers) else {
            return .failure(String(localized: "Une opération est déjà en cours pour un paquet."))
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
                activeOperationName = String(localized: "Mise à jour de \(package.displayName)")
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
                        localized: "\(package.displayName) : \(Self.errorDescription(for: error))"
                    )
                )
            }
        }
        await load(forceCatalogRefresh: true)
        if failures.isEmpty {
            return .success(String(localized: "\(completed) paquets mis à jour"))
        }
        let failureSummary = failures.formatted(.list(type: .and))
        return .failure(
            String(
                localized: "\(completed) paquets mis à jour, \(failures.count) en échec : \(failureSummary)"
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
        guard let operationProgress else {
            return String(localized: "\(activeOperationName), préparation par le NAS")
        }
        return String(
            localized: "\(activeOperationName), vérification de l’état \(operationProgress.statusChecks)"
        )
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
                localized: "\(packages.count) paquets, \(updateCount) mises à jour disponibles"
            )
        } else {
            base = String(localized: "\(packages.count) paquets installés")
        }
        if let catalogErrorMessage {
            return String(
                localized: "\(base). Catalogue indisponible : \(catalogErrorMessage)"
            )
        }
        return base
    }
}
