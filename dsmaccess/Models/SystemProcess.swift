//
//  SystemProcess.swift
//  dsmaccess
//
//  Gestionnaire des tâches du moniteur de ressources. Deux API distinctes et, piège
//  relevé sur DSM 7.4, deux unités de mémoire différentes : `SYNO.Core.System.Process`
//  compte en **Kio**, `SYNO.Core.System.ProcessGroup` en **octets**.
//
//  Second piège : les groupes sans mesure ne renvoient ni zéro ni `null` mais la chaîne
//  « - ». Le décodage souple la ramène à `nil`, et l'affichage doit alors dire qu'il n'y
//  a pas de valeur plutôt que d'écrire zéro, qui se lirait comme une mesure.
//

import Foundation

struct SystemProcessPage: nonisolated Decodable, Sendable {
    let process: [SystemProcess]
}

struct SystemProcess: nonisolated Decodable, Sendable, Identifiable {
    let pid: Int?
    let command: String?
    let cpuPercent: Int?
    /// Mémoire résidente, en Kio.
    let memoryKiB: Int?
    let sharedMemoryKiB: Int?
    /// Code d'état Linux brut : « R » en exécution, « S » en sommeil, « Z » zombie…
    let status: String?

    var id: String { pid.map(String.init) ?? command ?? "" }
    var name: String { command ?? String(localized: "Processus sans nom") }

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

/// Regroupement par service, tel que DSM le présente : « Plex Media Server » plutôt que
/// la liste de ses processus. C'est la vue lisible du gestionnaire des tâches.
struct ProcessGroup: nonisolated Decodable, Sendable, Identifiable {
    let name: String?
    /// Nom traduit par DSM. Souvent vide, d'où le repli sur `name`.
    let localizedName: String?
    let unitName: String?
    let cpuPercent: Double?
    /// Temps processeur cumulé, en secondes.
    let cpuTime: Double?
    /// Mémoire occupée, en **octets**.
    let memoryBytes: Int64?
    let readBytesPerSecond: Int64?
    let writeBytesPerSecond: Int64?
    let processCount: Int

    var id: String { unitName ?? name ?? "" }

    var displayName: String {
        if let localizedName, !localizedName.isEmpty { return localizedName }
        if let name, !name.isEmpty { return name }
        return unitName ?? ""
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
        cpuPercent = c.flexDouble(.cpuPercent)
        cpuTime = c.flexDouble(.cpuTime)
        memoryBytes = c.flexInt64(.memoryBytes)
        readBytesPerSecond = c.flexInt64(.readBytesPerSecond)
        writeBytesPerSecond = c.flexInt64(.writeBytesPerSecond)
        processCount = (try? c.decode([AnyDecodableProcess].self, forKey: .process))?.count ?? 0
    }

    /// Le détail des processus d'un groupe n'est pas exploité : seul leur nombre l'est.
    private struct AnyDecodableProcess: nonisolated Decodable, Sendable {}
}
