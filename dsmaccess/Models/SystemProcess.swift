//
//  SystemProcess.swift
//  dsmaccess
//
//  Task manager of the resource monitor. Two distinct APIs and, a pitfall found on
//  DSM 7.4, two different memory units: `SYNO.Core.System.Process` counts in **KiB**,
//  `SYNO.Core.System.ProcessGroup` in **bytes**.
//
//  Second pitfall: groups with no measurement return neither zero nor `null` but the
//  string "-". Lenient decoding turns it back into `nil`, and the display must then say
//  there is no value rather than writing zero, which would read as a measurement.
//
//  Third pitfall, and two opposite scales for the same quantity: the CPU load of a process
//  is already a percentage, that of a group is a fraction to be multiplied by 100.
//

import Foundation

struct SystemProcessPage: nonisolated Decodable, Sendable {
    let process: [SystemProcess]
}

struct SystemProcess: nonisolated Decodable, Sendable, Identifiable {
    let pid: Int?
    let command: String?
    let cpuPercent: Int?
    /// Resident memory, in KiB.
    let memoryKiB: Int?
    let sharedMemoryKiB: Int?
    /// Raw Linux state code: "R" running, "S" sleeping, "Z" zombie…
    let status: String?

    var id: String { pid.map(String.init) ?? command ?? "" }
    var name: String { command ?? String(localized: "tasks.process.unnamed") }

    /// Non-optional sort keys: a missing measurement sorts last rather than preventing the
    /// column from being sorted at all.
    var sortableCPU: Int { cpuPercent ?? -1 }
    var sortableMemory: Int { memoryKiB ?? -1 }

    enum CodingKeys: String, CodingKey {
        case pid, command, status
        case cpuPercent = "cpu"
        case memoryKiB = "mem"
        case sharedMemoryKiB = "mem_shared"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pid = c.flexInt(.pid)
        command = c.flexString(.command)
        cpuPercent = c.flexInt(.cpuPercent)
        memoryKiB = c.flexInt(.memoryKiB)
        sharedMemoryKiB = c.flexInt(.sharedMemoryKiB)
        status = c.flexString(.status)
    }
}

struct ProcessGroupPage: nonisolated Decodable, Sendable {
    let slices: [ProcessGroup]
}

/// Grouping by service, the way DSM presents it: "Plex Media Server" rather than the list
/// of its processes. This is the readable view of the task manager.
struct ProcessGroup: nonisolated Decodable, Sendable, Identifiable {
    let name: String?
    /// Despite its name, this field does not hold a translation: when DSM has no common name
    /// to give, it puts a **key from its own catalog** there ("storage_pool:raid_process")
    /// and leaves `name` empty. The two are never filled in at the same time.
    let localizedName: String?
    let unitName: String?
    /// CPU load as a percentage. DSM sends it as a **fraction** in `cpu_utilization` — its
    /// own client stores it in a field named `cpuFraction` and multiplies it by 100 to
    /// display it. Read as is, the whole column reads "0.0 %": a 1.2 % load arrives here
    /// as 0.0121.
    let cpuPercent: Double?
    /// Cumulative CPU time, in seconds.
    let cpuTime: Double?
    /// Memory in use, in **bytes**.
    let memoryBytes: Int64?
    let readBytesPerSecond: Int64?
    let writeBytesPerSecond: Int64?
    let processCount: Int

    var id: String { unitName ?? name ?? "" }

    /// See `SystemProcess.sortableCPU`: a measurement DSM did not provide must not block
    /// sorting, it goes to the end of the list.
    var sortableCPU: Double { cpuPercent ?? -1 }
    var sortableMemory: Int64 { memoryBytes ?? -1 }
    var sortableCPUTime: Double { cpuTime ?? -1 }
    var sortableReadRate: Int64 { readBytesPerSecond ?? -1 }
    var sortableWriteRate: Int64 { writeBytesPerSecond ?? -1 }

    var displayName: String {
        let candidates = [name, localizedName, unitName].compactMap { $0 }
        guard let raw = candidates.first(where: { !$0.isEmpty }) else { return "" }
        return Self.readable(raw)
    }

    /// When DSM does not translate, it leaves a key from its own catalog:
    /// "service:desktop_service", "storage_pool:raid_process". Its web client resolves it,
    /// which we cannot do. The key is therefore made readable rather than displayed raw —
    /// only its punctuation changes, nothing is guessed.
    ///
    /// Alarm rules receive the same keys in their `name` field: they rely on this
    /// conversion rather than writing a second one.
    static func readable(_ raw: String) -> String {
        guard raw.contains(":") || raw.contains("_") else { return raw }
        let tail = raw.split(separator: ":").last.map(String.init) ?? raw
        let words = tail.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    enum CodingKeys: String, CodingKey {
        case name, process
        case localizedName = "name_i18n"
        case unitName = "unit_name"
        case cpuPercent = "cpu_utilization"
        case cpuTime = "cpu_time"
        case memoryBytes = "memory"
        case readBytesPerSecond = "byte_read_per_sec"
        case writeBytesPerSecond = "byte_write_per_sec"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexString(.name)
        localizedName = c.flexString(.localizedName)
        unitName = c.flexString(.unitName)
        cpuPercent = c.flexDouble(.cpuPercent).map { $0 * 100 }
        cpuTime = c.flexDouble(.cpuTime)
        memoryBytes = c.flexInt64(.memoryBytes)
        readBytesPerSecond = c.flexInt64(.readBytesPerSecond)
        writeBytesPerSecond = c.flexInt64(.writeBytesPerSecond)
        processCount = (try? c.decode([AnyDecodableProcess].self, forKey: .process))?.count ?? 0
    }

    /// The details of a group's processes are not used: only their count is.
    private struct AnyDecodableProcess: nonisolated Decodable, Sendable {}
}
