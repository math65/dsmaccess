//
//  ContainerCreation.swift
//  dsmaccess
//
//  Building the creation profile of a new container.
//

import Foundation

/// A published port. Captured shape: `{container_port, host_port, type}`, and a host port of
/// `0` is kept as is — Docker then picks a free one when the container starts, which is what
/// makes duplicating a container possible without hunting for a spare port.
struct ContainerPortBinding: Identifiable, Equatable, Sendable {
    let id = UUID()
    var containerPort: Int
    var hostPort: Int
    var networkProtocol: String

    nonisolated init(containerPort: Int = 0, hostPort: Int = 0, networkProtocol: String = "tcp") {
        self.containerPort = containerPort
        self.hostPort = hostPort
        self.networkProtocol = networkProtocol
    }

    var fields: [String: DSMJSONValue] {
        [
            "container_port": .integer(containerPort),
            "host_port": .integer(hostPort),
            "type": .string(networkProtocol),
        ]
    }
}

/// A mounted folder. Captured shape: `{host_volume_file, is_directory, mount_point, type}`,
/// where `type` is `rw` or `ro` and the host path is relative to the shared folder.
struct ContainerVolumeBinding: Identifiable, Equatable, Sendable {
    let id = UUID()
    var hostPath: String
    var mountPoint: String
    var isReadOnly: Bool

    nonisolated init(hostPath: String = "", mountPoint: String = "", isReadOnly: Bool = false) {
        self.hostPath = hostPath
        self.mountPoint = mountPoint
        self.isReadOnly = isReadOnly
    }

    var fields: [String: DSMJSONValue] {
        [
            "host_volume_file": .string(hostPath),
            "is_directory": .boolean(true),
            "mount_point": .string(mountPoint),
            "type": .string(isReadOnly ? "ro" : "rw"),
        ]
    }
}

struct ContainerEnvironmentVariable: Identifiable, Equatable, Sendable {
    let id = UUID()
    var key: String
    var value: String

    nonisolated init(key: String = "", value: String = "") {
        self.key = key
        self.value = value
    }

    var fields: [String: DSMJSONValue] {
        ["key": .string(key), "value": .string(value)]
    }
}

/// What the creation screen collects, before it becomes a profile.
///
/// Ports, volumes and variables belong here and not in the settings screen: measured against
/// the NAS, `set` accepts them and applies nothing, while `create` honours all three.
struct ContainerDraft: Equatable, Sendable {
    var name = ""
    var image = ""
    var command = ""
    var restartsAutomatically = false
    var limitsMemory = false
    var memoryLimitMB = 512
    var ports: [ContainerPortBinding] = []
    var volumes: [ContainerVolumeBinding] = []
    var environment: [ContainerEnvironmentVariable] = []
    var startsImmediately = true

    /// DSM validates a container name client-side before sending it, and so do we: the NAS
    /// answers a bare 1306 that says nothing about what is wrong.
    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !trimmedName.isEmpty && !image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func profile() -> ContainerProfile {
        var fields: [String: DSMJSONValue] = [
            "name": .string(trimmedName),
            "image": .string(image.trimmingCharacters(in: .whitespacesAndNewlines)),
            "enable_restart_policy": .boolean(restartsAutomatically),
            "enable_publish_all_ports": .boolean(false),
            "privileged": .boolean(false),
            "use_host_network": .boolean(false),
            "memory_limit": .integer(limitsMemory ? memoryLimitMB * 1024 * 1024 : 0),
            "cpu_priority": .integer(0),
            "links": .array([]),
            "network_mode": .string("bridge"),
            "network": .array([.object(["driver": .string("bridge"), "name": .string("bridge")])]),
            "port_bindings": .array(ports.map { .object($0.fields) }),
            "volume_bindings": .array(volumes.map { .object($0.fields) }),
            "env_variables": .array(
                environment
                    .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .map { .object($0.fields) }
            ),
        ]
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !command.isEmpty {
            fields["cmd"] = .string(command)
        }
        return ContainerProfile(fields: fields)
    }
}
