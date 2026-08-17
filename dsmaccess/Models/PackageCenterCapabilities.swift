//
//  PackageCenterCapabilities.swift
//  dsmaccess
//
//  Capabilities actually advertised by SYNO.API.Info for Package Center.
//

import Foundation

struct PackageCenterCapabilities: Equatable, Sendable {
    let canListInstalledPackages: Bool
    let canBrowseCatalog: Bool
    let canInstallCatalogPackages: Bool
    let canInstallManualPackages: Bool
    let canInstallVerifiedUpdates: Bool
    let canRepairPackages: Bool
    let canControlPackages: Bool
    let canUninstallPackages: Bool
    let canManageSettings: Bool
    let canManagePackageSources: Bool
    let maximumVersions: [String: Int]
}

struct PackageOperationProgress: Equatable, Sendable {
    let taskID: String
    let statusChecks: Int
    let isFinished: Bool
    /// Name of the package this step is downloading. A package installed with its
    /// dependencies runs one of these per package, and saying which one is being fetched is
    /// the difference between a progress message and a spinner.
    var packageName: String?
    /// Position of the step in the plan and its length, both 1 when there is no dependency.
    var step: Int = 1
    var stepCount: Int = 1
}
