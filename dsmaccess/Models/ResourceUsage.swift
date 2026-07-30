//
//  ResourceUsage.swift
//  dsmaccess
//
//  Payload of SYNO.Core.System.Utilization (method=get): instantaneous NAS readings
//  (processor, memory, network). UNDOCUMENTED API: structure pinned on real responses,
//  fields optional out of caution. Numbers arrive sometimes as a JSON integer, sometimes
//  as a string depending on the DSM version → lenient decoding (`flexInt`).
//

import Foundation

struct ResourceUsage: nonisolated Decodable, Sendable {
    let cpu: CPU?
    let memory: Memory?
    let network: [Interface]?
    let disk: Activity?
    let space: Activity?

    enum CodingKeys: String, CodingKey { case cpu, memory, network, disk, space }

    /// Activity of a group of devices. DSM uses the same shape for disks (`disk`, each with
    /// its `type`) and for volumes (`space`), in both cases with a separate cumulative
    /// `device == "total"` entry.
    struct Activity: nonisolated Decodable, Sendable {
        let devices: [Device]
        let total: Device?

        enum CodingKeys: String, CodingKey { case disk, volume, total }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            devices = (try? c.decode([Device].self, forKey: .disk))
                ?? (try? c.decode([Device].self, forKey: .volume))
                ?? []
            total = try? c.decode(Device.self, forKey: .total)
        }
    }

    /// A disk or a volume. `read_byte`/`write_byte` are throughputs in bytes per second,
    /// `read_access`/`write_access` are access counts, `utilization` is a percentage.
    struct Device: nonisolated Decodable, Sendable, Identifiable {
        let device: String?
        let displayName: String?
        let type: String?
        let utilization: Int?
        let readBytesPerSecond: Int?
        let writeBytesPerSecond: Int?
        let readOperations: Int?
        let writeOperations: Int?

        var id: String { device ?? displayName ?? "" }
        /// Readable name, falling back on the hardware identifier when DSM gives none.
        var name: String { displayName ?? device ?? "" }

        enum CodingKeys: String, CodingKey {
            case device, type, utilization
            case displayName = "display_name"
            case readBytesPerSecond = "read_byte"
            case writeBytesPerSecond = "write_byte"
            case readOperations = "read_access"
            case writeOperations = "write_access"
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            device = c.flexString(.device)
            displayName = c.flexString(.displayName)
            type = c.flexString(.type)
            utilization = c.flexInt(.utilization)
            readBytesPerSecond = c.flexInt(.readBytesPerSecond)
            writeBytesPerSecond = c.flexInt(.writeBytesPerSecond)
            readOperations = c.flexInt(.readOperations)
            writeOperations = c.flexInt(.writeOperations)
        }
    }

    /// Processor loads as percentages (user / system / other), and the Unix load averages.
    /// The latter arrive **multiplied by one hundred** (`57` means 0.57): DSM's web client
    /// divides them before display, a contract read off its code.
    struct CPU: nonisolated Decodable, Sendable {
        let userLoad: Int?
        let systemLoad: Int?
        let otherLoad: Int?
        let oneMinuteLoad: Double?
        let fiveMinuteLoad: Double?
        let fifteenMinuteLoad: Double?

        enum CodingKeys: String, CodingKey {
            case userLoad = "user_load"
            case systemLoad = "system_load"
            case otherLoad = "other_load"
            case oneMinuteLoad = "1min_load"
            case fiveMinuteLoad = "5min_load"
            case fifteenMinuteLoad = "15min_load"
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userLoad = c.flexInt(.userLoad)
            systemLoad = c.flexInt(.systemLoad)
            otherLoad = c.flexInt(.otherLoad)
            oneMinuteLoad = c.flexInt(.oneMinuteLoad).map { Double($0) / 100 }
            fiveMinuteLoad = c.flexInt(.fiveMinuteLoad).map { Double($0) / 100 }
            fifteenMinuteLoad = c.flexInt(.fifteenMinuteLoad).map { Double($0) / 100 }
        }
    }

    /// RAM: percentage used and real/swap sizes (in KiB).
    struct Memory: nonisolated Decodable, Sendable {
        let realUsage: Int?     // %
        let totalReal: Int?     // KiB
        let availReal: Int?     // KiB
        let cached: Int?        // KiB
        let buffer: Int?        // KiB
        let swapUsage: Int?     // %

        /// Memory actually occupied, cache and buffers excluded. That is DSM's definition:
        /// on a NAS where the disk cache takes up almost all the memory, counting the cache
        /// would give 96% where DSM announces 17%, and the two figures would contradict each
        /// other on screen. Verified on DSM 7.4 on 2026-07-29.
        var usedReal: Int? {
            guard let totalReal, let availReal else { return nil }
            let used = totalReal - availReal - (cached ?? 0) - (buffer ?? 0)
            return used >= 0 ? used : nil
        }

        enum CodingKeys: String, CodingKey {
            case realUsage = "real_usage"
            case totalReal = "total_real"
            case availReal = "avail_real"
            case swapUsage = "swap_usage"
            case cached, buffer
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            realUsage = c.flexInt(.realUsage)
            totalReal = c.flexInt(.totalReal)
            availReal = c.flexInt(.availReal)
            cached = c.flexInt(.cached)
            buffer = c.flexInt(.buffer)
            swapUsage = c.flexInt(.swapUsage)
        }
    }

    /// Throughput of a network interface (bytes per second). DSM includes a synthetic
    /// `device == "total"` entry summing all interfaces.
    struct Interface: nonisolated Decodable, Sendable {
        let device: String?
        let rx: Int?            // bytes/s received
        let tx: Int?            // bytes/s sent

        enum CodingKeys: String, CodingKey { case device, rx, tx }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            device = try? c.decode(String.self, forKey: .device)
            rx = c.flexInt(.rx)
            tx = c.flexInt(.tx)
        }
    }
}
