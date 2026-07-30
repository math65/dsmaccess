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
    let requirements: PackageInstallationRequirements

    init(
        packageID: String,
        version: String,
        downloadURL: URL,
        checksum: String,
        fileSize: Int,
        isBeta: Bool,
        packageType: Int,
        requirements: PackageInstallationRequirements = PackageInstallationRequirements()
    ) {
        self.packageID = packageID
        self.version = version
        self.downloadURL = downloadURL
        self.checksum = checksum
        self.fileSize = fileSize
        self.isBeta = isBeta
        self.packageType = packageType
        self.requirements = requirements
    }

    var id: String {
        [
            packageID.lowercased(),
            version,
            String(isBeta),
            String(packageType),
            downloadURL.absoluteString,
        ].joined(separator: "|")
    }
}
