//
//  PackageInfo.swift
//  dsmaccess
//
//  Response of SYNO.Core.Package (method=list): the installed packages of Package Center.
//  UNDOCUMENTED API. Structure confirmed on DSM 7.4: id/name/version at the top level, and
//  the running/stopped state nested in `additional.status` ("running", "stop"…).
//

import Foundation

struct PackageList: nonisolated Decodable, Sendable {
    let packages: [PackageInfo]?
}

/// Response of the Package Center catalogue.
struct ServerPackageList: nonisolated Decodable, Sendable {
    let packages: [ServerPackage]?
}

struct ServerPackage: nonisolated Decodable, Sendable {
    let id: String?
    let version: String?
    let link: String?
    let md5: String?
    let size: Int?
    let beta: Bool?
    let source: String?
    let type: Int?
    let dependencyServers: DSMJSONValue?
    let dependencyPackages: DSMJSONValue?
    let conflictingPackages: DSMJSONValue?
    let breakingPackages: DSMJSONValue?
    let replacementPackages: DSMJSONValue?
    let installType: String?
    let installOnColdStorage: DSMJSONValue?
    let license: DSMJSONValue?
    let installPages: DSMJSONValue?

    private enum CodingKeys: String, CodingKey {
        case id, version, link, md5, size, beta, source, type
        case dependencyServers = "depsers"
        case dependencyPackages = "deppkgs"
        case conflictingPackages = "conflictpkgs"
        case breakingPackages = "breakpkgs"
        case replacementPackages = "replacepkgs"
        case installType = "install_type"
        case installOnColdStorage = "install_on_cold_storage"
        case license = "licence"
        case installPages = "install_pages"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.flexString(.id)
        version = container.flexString(.version)
        link = container.flexString(.link)
        md5 = container.flexString(.md5)
        size = container.flexInt(.size)
        beta = container.flexBool(.beta)
        source = container.flexString(.source)
        type = container.flexInt(.type)
        dependencyServers = try container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .dependencyServers
        )
        dependencyPackages = try container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .dependencyPackages
        )
        conflictingPackages = try container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .conflictingPackages
        )
        breakingPackages = try container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .breakingPackages
        )
        replacementPackages = try container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .replacementPackages
        )
        installType = container.flexString(.installType)
        installOnColdStorage = try container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .installOnColdStorage
        )
        license = try container.decodeIfPresent(DSMJSONValue.self, forKey: .license)
        installPages = try container.decodeIfPresent(DSMJSONValue.self, forKey: .installPages)
    }
}

struct PackageInfo: nonisolated Decodable, Identifiable, Sendable {
    let pkgId: String
    let name: String?
    let version: String?
    let additional: Additional?

    /// Extra fields requested through the API's `additional` parameter.
    struct Additional: nonisolated Decodable, Sendable {
        let status: String?
        let installType: String?
        /// Can the package be started/stopped? (absent for packages that cannot be driven).
        let startable: Bool?
        /// Can the package be uninstalled from the UI? (false for some system packages).
        let ctlUninstall: Bool?
        /// Does the package offer custom uninstall options in DSM?
        let isUninstallPages: Bool?

        enum CodingKeys: String, CodingKey {
            case status
            case installType = "install_type"
            case startable
            case ctlUninstall = "ctl_uninstall"
            case isUninstallPages = "is_uninstall_pages"
        }
    }

    enum CodingKeys: String, CodingKey {
        case pkgId = "id"
        case name, version, additional
    }

    var id: String { pkgId }

    /// Displayed name: the name supplied, otherwise the identifier.
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return pkgId
    }

    /// Translated state (running / stopped).
    var statusText: String {
        let status = additional?.status?.lowercased()
        switch status {
        case "running", "start", "started": return String(localized: "common.status.in_progress")
        case "stop", "stopped", "stopping": return String(localized: "common.status.stopped")
        case .some(let value) where Self.requiresAttention(value):
            return String(localized: "common.status.repair_required")
        case .some(let value) where !value.isEmpty:
            return String(localized: "packages.dsm_status.value", defaultValue: "DSM status: \(value)")
        default: return "—"
        }
    }

    /// True if the package is currently running (same state logic as `statusText`).
    var isRunning: Bool {
        switch additional?.status?.lowercased() {
        case "running", "start", "started": return true
        default: return false
        }
    }

    var isStopped: Bool {
        switch additional?.status?.lowercased() {
        case "stop", "stopped", "stopping": true
        default: false
        }
    }

    var requiresAttention: Bool {
        guard let status = additional?.status?.lowercased() else { return false }
        return Self.requiresAttention(status)
    }

    private static func requiresAttention(_ status: String) -> Bool {
        ["repair", "repairing", "broken", "error", "corrupt", "corrupted"].contains(status)
            || status.hasPrefix("repair_")
            || status.hasPrefix("broken_")
            || status.hasPrefix("error_")
            || status.hasPrefix("corrupt_")
    }

    /// True if the package can be started/stopped (some system packages cannot).
    var canStartStop: Bool { additional?.startable == true }

    /// True if the package can be uninstalled from the app (some system packages cannot).
    var canUninstall: Bool { additional?.ctlUninstall == true }

    /// True if the package offers uninstall options in DSM (not exposed here).
    var hasUninstallOptions: Bool { additional?.isUninstallPages == true }

    /// Uninstalling this package goes through a DSM assistant the app does not reproduce.
    /// The table says so rather than letting the user discover it at the last step.
    var uninstallDescription: String {
        hasUninstallOptions
            ? String(localized: "packages.uninstall.assistant_required.title")
            : "—"
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableName: String { displayName }
    var sortableVersion: String { version ?? "" }
    var sortableStatus: String { statusText }
    /// Sorted as text like `NASConnection.sortableTwoFactor`: `Bool` is not `Comparable`.
    var sortableUninstall: String { hasUninstallOptions ? "1" : "0" }
}
