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
    case unknown(String)

    nonisolated init(rawValue: String) {
        switch rawValue.uppercased() {
        case "RUNNING": self = .running
        case "STOPPED": self = .stopped
        default: self = .unknown(rawValue)
        }
    }

    var isRunning: Bool { self == .running }

    /// Written out in full: DSM only carries this state in the colour of a dot.
    var localizedName: String {
        switch self {
        case .running: String(localized: "common.status.running")
        case .stopped: String(localized: "common.status.stopped")
        case .unknown(let value): value.isEmpty ? String(localized: "common.status.unknown") : value
        }
    }

    /// Sort key: running projects first, then stopped, then whatever DSM invents next.
    var sortRank: Int {
        switch self {
        case .running: 0
        case .stopped: 1
        case .unknown: 2
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
