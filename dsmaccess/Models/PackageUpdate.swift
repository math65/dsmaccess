//
//  PackageUpdate.swift
//  dsmaccess
//
//  Metadata required to update an official package.
//

import Foundation

struct PackageUpdate: Equatable, Identifiable, Sendable {
    let packageID: String
    let version: String
    let downloadURL: URL
    let checksum: String
    let fileSize: Int
    let isBeta: Bool
    let packageType: Int
    let origin: PackageCatalogOrigin
    /// Name DSM displays ("Synology Drive Server"), as opposed to the technical identifier.
    let displayName: String
    let summary: String?
    let maintainer: String?
    /// Category identifiers; empty for a third-party package, which DSM does not classify.
    let categories: [String]
    let changelog: String?
    let requirements: PackageInstallationRequirements

    init(
        packageID: String,
        version: String,
        downloadURL: URL,
        checksum: String,
        fileSize: Int,
        isBeta: Bool,
        packageType: Int,
        origin: PackageCatalogOrigin = .synology,
        displayName: String? = nil,
        summary: String? = nil,
        maintainer: String? = nil,
        categories: [String] = [],
        changelog: String? = nil,
        requirements: PackageInstallationRequirements = PackageInstallationRequirements()
    ) {
        self.packageID = packageID
        self.version = version
        self.downloadURL = downloadURL
        self.checksum = checksum
        self.fileSize = fileSize
        self.isBeta = isBeta
        self.packageType = packageType
        self.origin = origin
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = trimmedName?.isEmpty == false ? trimmedName! : packageID
        self.summary = summary
        self.maintainer = maintainer
        self.categories = categories
        self.changelog = changelog
        self.requirements = requirements
    }

    var id: String {
        [
            packageID.lowercased(),
            version,
            String(isBeta),
            String(packageType),
            origin.rawValue,
            downloadURL.absoluteString,
        ].joined(separator: "|")
    }

    /// Non-optional sort key: a package without a publisher sorts first rather than keeping
    /// its column unsortable.
    var sortableMaintainer: String { maintainer ?? "" }
    var sortableOrigin: String { origin.name }

    var betaDescription: String {
        isBeta
            ? String(localized: "common.answer.yes")
            : String(localized: "common.answer.no")
    }

    /// Sorted as text like `NASConnection.sortableTwoFactor`: `Bool` is not `Comparable`, and
    /// the column must be sortable like the others.
    var sortableBeta: String { isBeta ? "1" : "0" }
}
