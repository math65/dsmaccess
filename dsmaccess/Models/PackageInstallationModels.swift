//
//  PackageInstallationModels.swift
//  dsmaccess
//
//  Payloads used by DSM Package Center installations.
//

import Foundation

struct PackageInstallationRequirements: Equatable, Sendable {
    var dependencyServers: DSMJSONValue?
    var dependencyPackages: DSMJSONValue?
    var conflictingPackages: DSMJSONValue?
    var breakingPackages: DSMJSONValue?
    var replacementPackages: DSMJSONValue?
    var installType: String
    var installOnColdStorage: DSMJSONValue?
    var hasLicenseAgreement: Bool
    var hasCustomInstallPages: Bool

    init(
        dependencyServers: DSMJSONValue? = nil,
        dependencyPackages: DSMJSONValue? = nil,
        conflictingPackages: DSMJSONValue? = nil,
        breakingPackages: DSMJSONValue? = nil,
        replacementPackages: DSMJSONValue? = nil,
        installType: String = "",
        installOnColdStorage: DSMJSONValue? = nil,
        hasLicenseAgreement: Bool = false,
        hasCustomInstallPages: Bool = false
    ) {
        self.dependencyServers = dependencyServers
        self.dependencyPackages = dependencyPackages
        self.conflictingPackages = conflictingPackages
        self.breakingPackages = breakingPackages
        self.replacementPackages = replacementPackages
        self.installType = installType
        self.installOnColdStorage = installOnColdStorage
        self.hasLicenseAgreement = hasLicenseAgreement
        self.hasCustomInstallPages = hasCustomInstallPages
    }

    var requiresInteractiveInstaller: Bool {
        hasLicenseAgreement || hasCustomInstallPages
    }
}

struct PackageInstallQueue: nonisolated Decodable, Sendable {
    let brokenPackages: [String]
    let conflictingPackages: [String]
    let missingPackages: [String]
    let pausedPackages: [String]
    let replacementPackages: [String]
    let queue: [PackageInstallQueueItem]

    private enum CodingKeys: String, CodingKey {
        case brokenPackages = "broken_pkgs"
        case conflictingPackages = "conflicted_pkgs"
        case missingPackages = "non_exist_pkgs"
        case pausedPackages = "paused_pkgs"
        case replacementPackages = "replaced_pkgs"
        case queue
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        brokenPackages = try container.decodeIfPresent([String].self, forKey: .brokenPackages) ?? []
        conflictingPackages = try container.decodeIfPresent(
            [String].self,
            forKey: .conflictingPackages
        ) ?? []
        missingPackages = try container.decodeIfPresent([String].self, forKey: .missingPackages) ?? []
        pausedPackages = try container.decodeIfPresent([String].self, forKey: .pausedPackages) ?? []
        replacementPackages = try container.decodeIfPresent(
            [String].self,
            forKey: .replacementPackages
        ) ?? []
        queue = try container.decodeIfPresent([PackageInstallQueueItem].self, forKey: .queue) ?? []
    }
}

struct PackageInstallQueueItem: nonisolated Decodable, Equatable, Sendable {
    let packageID: String
    /// Missing on some DSM 7.4 builds (90075 only returns pkg/beta/volume).
    let operation: String?
    let version: String?
    let isBeta: Bool

    private enum CodingKeys: String, CodingKey {
        case packageID = "pkg"
        case operation, version, beta
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageID = try container.requiredFlexString(.packageID)
        operation = container.flexString(.operation)
        version = container.flexString(.version)
        isBeta = container.flexBool(.beta) ?? false
    }
}

struct PackageInstallationMetadata: nonisolated Decodable, Sendable {
    let taskID: String?
    let filename: String?
    let packageID: String
    let name: String?
    let version: String?
    let status: String?
    let installType: String
    let installOnColdStorage: Bool
    let breakingPackages: DSMJSONValue?
    let replacementPackages: DSMJSONValue?
    let license: DSMJSONValue?
    let installPages: DSMJSONValue?

    private struct Additional: nonisolated Decodable, Sendable {
        let status: String?
    }

    private enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case alternateTaskID = "taskid"
        case filename
        case packageID = "id"
        case name, version, status, additional
        case installType = "install_type"
        case installOnColdStorage = "install_on_cold_storage"
        case breakingPackages = "break_pkgs"
        case alternateBreakingPackages = "breakpkgs"
        case replacementPackages = "replace_pkgs"
        case alternateReplacementPackages = "replacepkgs"
        case license = "licence"
        case installPages = "install_pages"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskID = container.flexString(.taskID) ?? container.flexString(.alternateTaskID)
        filename = container.flexString(.filename)
        packageID = try container.requiredFlexString(.packageID)
        name = container.flexString(.name)
        version = container.flexString(.version)
        let additional = try container.decodeIfPresent(Additional.self, forKey: .additional)
        status = container.flexString(.status) ?? additional?.status
        installType = container.flexString(.installType) ?? ""
        installOnColdStorage = container.flexBool(.installOnColdStorage) ?? false
        breakingPackages = try container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .breakingPackages
        ) ?? container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .alternateBreakingPackages
        )
        replacementPackages = try container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .replacementPackages
        ) ?? container.decodeIfPresent(
            DSMJSONValue.self,
            forKey: .alternateReplacementPackages
        )
        license = try container.decodeIfPresent(DSMJSONValue.self, forKey: .license)
        installPages = try container.decodeIfPresent(DSMJSONValue.self, forKey: .installPages)
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return packageID
    }

    var requiresInteractiveInstaller: Bool {
        license?.hasContent == true
            || installPages?.hasContent == true
    }

    var isAlreadyInstalled: Bool {
        guard let status else { return false }
        return status.lowercased() != "non_installed"
    }
}

struct PackageCompoundData: nonisolated Decodable, Sendable {
    let hasFailure: Bool
    let results: [PackageCompoundResult]

    private enum CodingKeys: String, CodingKey {
        case hasFailure = "has_fail"
        case results = "result"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasFailure = container.flexBool(.hasFailure) ?? false
        results = try container.decodeIfPresent([PackageCompoundResult].self, forKey: .results) ?? []
    }
}

struct PackageCompoundResult: nonisolated Decodable, Sendable {
    let success: Bool
    let error: DSMErrorBody?
}
