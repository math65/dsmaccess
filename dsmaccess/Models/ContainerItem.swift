//
//  ContainerItem.swift
//  dsmaccess
//
//  Containers and logs exposed by Container Manager.
//

import Foundation

struct ContainerItem: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let image: String?
    let status: String
    let createdAt: Int64?
    let startedAt: String?
    let uptimeSeconds: Int64?
    let autoRestart: Bool
    let cpuPercent: Double?
    let memoryBytes: Int64?

    var isRunning: Bool {
        let value = status.lowercased()
        return value == "running" || value.hasPrefix("up")
    }

    /// Sort keys for the containers table. Running first, and containers without a
    /// measurement last rather than mixed in with the ones reporting zero.
    var sortableState: Int { isRunning ? 0 : 1 }
    var sortableImage: String { image ?? "" }
    var sortableCPU: Double { cpuPercent ?? -1 }
    var sortableMemory: Int64 { memoryBytes ?? -1 }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case image
        case status
        case state
        case runtimeState = "State"
        case createdAt = "created"
        case startedAt = "started"
        case uptimeSeconds = "up_time"
        case autoRestart = "enable_auto_restart"
        case cpuPercent = "cpu"
        case legacyCPUPercent = "cpu_percent"
        case memoryBytes = "memory"
        case legacyMemoryBytes = "memory_usage"
    }

    private enum RuntimeStateCodingKeys: String, CodingKey {
        case startedAt = "StartedAt"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        id = values.flexString(.id) ?? name
        image = values.flexString(.image)
        status = values.flexString(.status) ?? values.flexString(.state) ?? "unknown"
        createdAt = values.flexInt64(.createdAt)
        let nestedStartedAt: String?
        if values.contains(.runtimeState), !(try values.decodeNil(forKey: .runtimeState)) {
            let runtimeState = try values.nestedContainer(
                keyedBy: RuntimeStateCodingKeys.self,
                forKey: .runtimeState
            )
            nestedStartedAt = runtimeState.flexString(.startedAt)
        } else {
            nestedStartedAt = nil
        }
        startedAt = nestedStartedAt ?? values.flexString(.startedAt)
        uptimeSeconds = values.flexInt64(.uptimeSeconds)
        autoRestart = values.flexBool(.autoRestart) ?? false
        cpuPercent = Self.percent(in: values, forKey: .cpuPercent)
            ?? Self.percent(in: values, forKey: .legacyCPUPercent)
        memoryBytes = values.flexInt64(.memoryBytes) ?? values.flexInt64(.legacyMemoryBytes)
    }

    func applying(_ resource: ContainerResource) -> ContainerItem {
        ContainerItem(
            id: id,
            name: name,
            image: image,
            status: status,
            createdAt: createdAt,
            startedAt: startedAt,
            uptimeSeconds: uptimeSeconds,
            autoRestart: autoRestart,
            cpuPercent: resource.cpuPercent,
            memoryBytes: resource.memoryBytes
        )
    }

    private init(
        id: String,
        name: String,
        image: String?,
        status: String,
        createdAt: Int64?,
        startedAt: String?,
        uptimeSeconds: Int64?,
        autoRestart: Bool,
        cpuPercent: Double?,
        memoryBytes: Int64?
    ) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
        self.autoRestart = autoRestart
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
    }

    private static nonisolated func percent(
        in values: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        values.flexString(key).flatMap {
            Double($0.replacingOccurrences(of: "%", with: ""))
        }
    }
}

struct ContainerList: nonisolated Decodable, Sendable {
    let containers: [ContainerItem]

    enum CodingKeys: String, CodingKey { case containers }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        containers = try values.decodeIfPresent([ContainerItem].self, forKey: .containers) ?? []
    }
}

struct ContainerResource: nonisolated Decodable, Hashable, Sendable {
    let name: String
    let cpuPercent: Double
    let memoryBytes: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case cpuPercent = "cpu"
        case memoryBytes = "memory"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        guard let cpuText = values.flexString(.cpuPercent),
              let decodedCPU = Double(cpuText.replacingOccurrences(of: "%", with: "")) else {
            throw DecodingError.dataCorruptedError(
                forKey: .cpuPercent,
                in: values,
                debugDescription: "Required container CPU usage is missing or malformed."
            )
        }
        guard let decodedMemory = values.flexInt64(.memoryBytes) else {
            throw DecodingError.dataCorruptedError(
                forKey: .memoryBytes,
                in: values,
                debugDescription: "Required container memory usage is missing or malformed."
            )
        }
        cpuPercent = decodedCPU
        memoryBytes = decodedMemory
    }
}

struct ContainerResourceList: nonisolated Decodable, Sendable {
    let resources: [ContainerResource]

    enum CodingKeys: String, CodingKey { case resources }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        resources = try values.decodeIfPresent([ContainerResource].self, forKey: .resources) ?? []
    }
}

struct ContainerLogEntry: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let timestamp: String?
    let stream: String?
    let message: String

    enum CodingKeys: String, CodingKey {
        case id = "docid"
        case timestamp = "created"
        case legacyTimestamp = "time"
        case alternateTimestamp = "timestamp"
        case stream
        case message = "text"
        case legacyMessage = "log"
        case alternateMessage = "message"
    }

    nonisolated init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            let position = decoder.codingPath.last?.intValue ?? 0
            id = "fallback:\(position):\(value.hashValue)"
            timestamp = nil
            stream = nil
            message = value
            return
        }

        let values = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = values.flexString(.timestamp)
            ?? values.flexString(.legacyTimestamp)
            ?? values.flexString(.alternateTimestamp)
        stream = values.flexString(.stream)
        message = values.flexString(.message)
            ?? values.flexString(.legacyMessage)
            ?? values.flexString(.alternateMessage)
            ?? ""
        let position = decoder.codingPath.last?.intValue ?? 0
        id = values.flexString(.id)
            ?? "fallback:\(position):\(timestamp ?? ""):\(message.hashValue)"
    }
}

struct ContainerLogList: nonisolated Decodable, Sendable {
    let logs: [ContainerLogEntry]

    enum CodingKeys: String, CodingKey { case logs }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        logs = try values.decodeIfPresent([ContainerLogEntry].self, forKey: .logs) ?? []
    }
}

enum ContainerAction: String, Sendable {
    case start
    case stop
    case restart
}

/// A container's creation profile, as `SYNO.Docker.Container get` returns it.
///
/// DSM's own Settings screen sends the **whole** profile back to `set`, with only the edited
/// fields changed. So the profile is kept as received rather than modelled: the app edits the
/// few fields it understands and hands the rest back untouched, which is what keeps a field it
/// has never heard of from being dropped on save.
struct ContainerProfile: Equatable, Sendable {
    private(set) var fields: [String: DSMJSONValue]

    nonisolated init(fields: [String: DSMJSONValue]) {
        self.fields = fields
    }

    /// Bytes, `0` meaning no limit — DSM's own "unlimited".
    var memoryLimit: Int64 {
        get {
            switch fields["memory_limit"] {
            case .integer(let value): Int64(value)
            case .number(let value): Int64(value)
            default: 0
            }
        }
        set { fields["memory_limit"] = .integer(Int(newValue)) }
    }

    var restartsAutomatically: Bool {
        get {
            if case .boolean(let value) = fields["enable_restart_policy"] { value } else { false }
        }
        set { fields["enable_restart_policy"] = .boolean(newValue) }
    }

    /// DSM shows this as Low / Medium / High; the wire value is a plain number.
    var cpuPriority: Int {
        get {
            if case .integer(let value) = fields["cpu_priority"] { value } else { 0 }
        }
        set { fields["cpu_priority"] = .integer(newValue) }
    }

    var name: String {
        if case .string(let value) = fields["name"] { value } else { "" }
    }
}

/// Reply of `SYNO.Docker.Container get`: the live details, and the creation profile.
struct ContainerProfileResponse: nonisolated Decodable, Sendable {
    let profile: ContainerProfile

    private enum CodingKeys: String, CodingKey {
        case profile
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = ContainerProfile(
            fields: try container.decode([String: DSMJSONValue].self, forKey: .profile)
        )
    }
}

/// One process inside a running container. Captured on DSM 7.4: `pid` arrives as a string,
/// `cpu` and `memoryPercent` as fractions of a percent, `start` as a short human date.
struct ContainerProcess: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let pid: String
    let command: String
    let cpuPercent: Double?
    let memoryBytes: Int64?
    let startedText: String?

    var id: String { pid }

    enum CodingKeys: String, CodingKey {
        case pid
        case command
        case cpuPercent = "cpu"
        case memoryBytes = "memory"
        case startedText = "start"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pid = try values.requiredFlexString(.pid)
        command = values.flexString(.command) ?? ""
        cpuPercent = values.flexDouble(.cpuPercent)
        memoryBytes = values.flexInt64(.memoryBytes)
        startedText = values.flexString(.startedText).flatMap { $0.isEmpty ? nil : $0 }
    }
}

struct ContainerProcessList: nonisolated Decodable, Sendable {
    let processes: [ContainerProcess]

    enum CodingKeys: String, CodingKey { case processes }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        processes = try values.decodeIfPresent([ContainerProcess].self, forKey: .processes) ?? []
    }
}
