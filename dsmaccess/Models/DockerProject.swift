//
//  DockerProject.swift
//  dsmaccess
//
//  Compose projects exposed by Container Manager.
//

import Foundation

enum DockerProjectStatus: nonisolated Hashable, Sendable {
    case running
    case stopped
    /// Observed on DSM 7.4 after a compose build whose image pull was refused.
    case buildFailed
    case unknown(String)

    nonisolated init(rawValue: String) {
        switch rawValue.uppercased() {
        case "RUNNING": self = .running
        case "STOPPED": self = .stopped
        case "BUILD_FAILED": self = .buildFailed
        default: self = .unknown(rawValue)
        }
    }

    var isRunning: Bool { self == .running }

    /// Written out in full: DSM only carries this state in the colour of a dot.
    var localizedName: String {
        switch self {
        case .running: String(localized: "common.status.running")
        case .stopped: String(localized: "common.status.stopped")
        case .buildFailed: String(localized: "containers.project.status.build_failed")
        case .unknown(let value): value.isEmpty ? String(localized: "common.status.unknown") : value
        }
    }

    /// Sort key: running projects first, then the states that need attention.
    var sortRank: Int {
        switch self {
        case .running: 0
        case .stopped: 1
        case .buildFailed: 2
        case .unknown: 3
        }
    }
}

struct DockerProject: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let status: DockerProjectStatus
    let containerIDs: [String]
    let createdAt: Date?
    let updatedAt: Date?
    let isPackage: Bool
    let servicePortalName: String?
    let servicePortalPort: Int?
    let servicePortalProtocol: String?
    let isServicePortalEnabled: Bool
    /// The docker-compose file itself. Only `get` returns it; `list` leaves it nil.
    let content: String?

    var containerCount: Int { containerIDs.count }

    var isRunning: Bool { status.isRunning }

    /// DSM's own naming rule, read from the client-side validation of its creation wizard
    /// (`^[a-z0-9][a-z0-9_-]*$`): a lowercase letter or a digit first, then lowercase letters,
    /// digits, `_` and `-`. Sending anything else answers error 2206.
    static nonisolated func isValidName(_ name: String) -> Bool {
        func isLowercaseOrDigit(_ character: Character) -> Bool {
            character.isASCII && (character.isLowercase || character.isNumber)
        }
        guard let first = name.first, isLowercaseOrDigit(first) else { return false }
        return name.dropFirst().allSatisfy {
            isLowercaseOrDigit($0) || $0 == "_" || $0 == "-"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case status
        case containerIDs = "containerIds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPackage = "is_package"
        case servicePortalName = "service_portal_name"
        case servicePortalPort = "service_portal_port"
        case servicePortalProtocol = "service_portal_protocol"
        case isServicePortalEnabled = "enable_service_portal"
        case content
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.requiredFlexString(.id)
        name = try values.requiredFlexString(.name)
        path = values.flexString(.path) ?? ""
        status = DockerProjectStatus(rawValue: values.flexString(.status) ?? "")
        containerIDs = try values.decodeIfPresent([String].self, forKey: .containerIDs) ?? []
        createdAt = Self.date(values.flexString(.createdAt))
        updatedAt = Self.date(values.flexString(.updatedAt))
        isPackage = values.flexBool(.isPackage) ?? false
        servicePortalName = values.flexString(.servicePortalName)?.nilWhenEmpty
        servicePortalPort = values.flexInt(.servicePortalPort)
        servicePortalProtocol = values.flexString(.servicePortalProtocol)?.nilWhenEmpty
        isServicePortalEnabled = values.flexBool(.isServicePortalEnabled) ?? false
        content = values.flexString(.content)?.nilWhenEmpty
    }

    /// DSM 7.4 stamps these with sub-second precision (`2025-04-08T20:41:48.391487Z`), which the
    /// plain ISO-8601 parser rejects.
    private static nonisolated func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        if let date = try? Date(text, strategy: .iso8601.time(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: .iso8601)
    }
}

/// `SYNO.Docker.Project list` keys its projects by identifier instead of returning an array.
struct DockerProjectList: nonisolated Decodable, Sendable {
    let projects: [DockerProject]

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.singleValueContainer()
        let keyed = try values.decode([String: DockerProject].self)
        projects = Array(keyed.values)
    }
}

/// Result of a `*_stream` action. These methods answer with plain text rather than the usual
/// JSON envelope, and report their outcome in a trailing `Exit Code:` line.
struct DockerStreamResult: nonisolated Equatable, Sendable {
    let lines: [String]
    let exitCode: Int?

    var succeeded: Bool { exitCode == 0 }

    nonisolated init(output: String) {
        var parsedExitCode: Int?
        var collected: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let code = Self.exitCode(in: trimmed) {
                parsedExitCode = code
                continue
            }
            collected.append(trimmed)
        }
        lines = collected
        exitCode = parsedExitCode
    }

    private static nonisolated func exitCode(in line: String) -> Int? {
        let marker = "Exit Code:"
        guard line.hasPrefix(marker) else { return nil }
        return Int(line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
    }
}

/// What `get_share_info` reports about a candidate folder. DSM asks this before creating a
/// project, to offer reusing a compose file the folder already holds. The three fields always
/// come back, empty rather than absent when the folder holds nothing.
struct DockerProjectShareInfo: nonisolated Decodable, Sendable {
    let hasComposeFile: Bool
    /// The compose file already in the folder, empty when there is none.
    let content: String
    /// Absolute path (`/volume1/…`), where the folder is chosen as a share-relative one.
    let composePath: String

    enum CodingKeys: String, CodingKey {
        case hasComposeFile = "is_docker_compose_yml_exist"
        case content
        case composePath = "compose_path"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hasComposeFile = values.flexBool(.hasComposeFile) ?? false
        content = values.flexString(.content) ?? ""
        composePath = values.flexString(.composePath) ?? ""
    }
}

/// What `create` answers. `services` lists the compose services DSM parsed out of the file.
struct DockerProjectCreation: nonisolated Decodable, Sendable {
    let id: String
    let name: String
    let services: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case services
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.requiredFlexString(.id)
        name = values.flexString(.name) ?? ""
        services = try values.decodeIfPresent([String].self, forKey: .services) ?? []
    }
}

enum DockerProjectAction: String, CaseIterable, Sendable {
    case start = "start_stream"
    case stop = "stop_stream"
    case restart = "restart_stream"
    case build = "build_stream"
    case clean = "clean_stream"

    var isDestructive: Bool {
        switch self {
        case .start, .stop, .restart, .build: false
        case .clean: true
        }
    }
}

private extension String {
    var nilWhenEmpty: String? { isEmpty ? nil : self }
}
