//
//  PackageInstallationModels.swift
//  dsmaccess
//
//  Charges utiles utilisées par les installations du Centre de paquets DSM.
//

import Foundation

enum PackageJSONValue: Codable, Equatable, Sendable {
    case null
    case boolean(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([PackageJSONValue])
    case object([String: PackageJSONValue])

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([PackageJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: PackageJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported Package Center JSON value."
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .boolean(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    var hasContent: Bool {
        switch self {
        case .null:
            false
        case .string(let value):
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let value):
            !value.isEmpty
        case .object(let value):
            !value.isEmpty
        case .boolean, .integer, .number:
            true
        }
    }
}

struct PackageInstallationRequirements: Equatable, Sendable {
    var dependencyServers: PackageJSONValue?
    var dependencyPackages: PackageJSONValue?
    var conflictingPackages: PackageJSONValue?
    var breakingPackages: PackageJSONValue?
    var replacementPackages: PackageJSONValue?
    var installType: String
    var installOnColdStorage: PackageJSONValue?
    var hasLicenseAgreement: Bool
    var hasCustomInstallPages: Bool

    init(
        dependencyServers: PackageJSONValue? = nil,
        dependencyPackages: PackageJSONValue? = nil,
        conflictingPackages: PackageJSONValue? = nil,
        breakingPackages: PackageJSONValue? = nil,
        replacementPackages: PackageJSONValue? = nil,
        installType: String = "",
        installOnColdStorage: PackageJSONValue? = nil,
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
    /// Absent sur certaines builds DSM 7.4 (90075 renvoie seulement pkg/beta/volume).
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
    let breakingPackages: PackageJSONValue?
    let replacementPackages: PackageJSONValue?
    let license: PackageJSONValue?
    let installPages: PackageJSONValue?

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
            PackageJSONValue.self,
            forKey: .breakingPackages
        ) ?? container.decodeIfPresent(
            PackageJSONValue.self,
            forKey: .alternateBreakingPackages
        )
        replacementPackages = try container.decodeIfPresent(
            PackageJSONValue.self,
            forKey: .replacementPackages
        ) ?? container.decodeIfPresent(
            PackageJSONValue.self,
            forKey: .alternateReplacementPackages
        )
        license = try container.decodeIfPresent(PackageJSONValue.self, forKey: .license)
        installPages = try container.decodeIfPresent(PackageJSONValue.self, forKey: .installPages)
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
