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
//  Troisième piège, et deux échelles opposées pour la même grandeur : la charge processeur
//  d'un processus est déjà un pourcentage, celle d'un groupe est une fraction à multiplier
//  par 100.
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

    /// Clés de tri non optionnelles : une mesure absente se range en dernier plutôt que
    /// d'empêcher le tri de la colonne.
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

/// Regroupement par service, tel que DSM le présente : « Plex Media Server » plutôt que
/// la liste de ses processus. C'est la vue lisible du gestionnaire des tâches.
struct ProcessGroup: nonisolated Decodable, Sendable, Identifiable {
    let name: String?
    /// Malgré son nom, ce champ ne contient pas une traduction : quand DSM n'a pas de nom
    /// courant à donner, il y met une **clé de son catalogue** (« storage_pool:raid_process »)
    /// et laisse `name` vide. Les deux ne sont jamais renseignés en même temps.
    let localizedName: String?
    let unitName: String?
    /// Charge processeur en pourcentage. DSM l'envoie sous forme de **fraction** dans
    /// `cpu_utilization` — son propre client la range dans un champ nommé `cpuFraction` et la
    /// multiplie par 100 pour l'afficher. Lue telle quelle, la colonne entière s'écrit
    /// « 0,0 % » : 1,2 % de charge arrive ici en 0,0121.
    let cpuPercent: Double?
    /// Temps processeur cumulé, en secondes.
    let cpuTime: Double?
    /// Mémoire occupée, en **octets**.
    let memoryBytes: Int64?
    let readBytesPerSecond: Int64?
    let writeBytesPerSecond: Int64?
    let processCount: Int

    var id: String { unitName ?? name ?? "" }

    /// Voir `SystemProcess.sortableCPU` : une mesure que DSM n'a pas fournie ne doit pas
    /// bloquer le tri, elle se range en fin de liste.
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

    /// Quand DSM ne traduit pas, il laisse une clé de son propre catalogue :
    /// « service:desktop_service », « storage_pool:raid_process ». Son client web la
    /// résout, ce que nous ne pouvons pas faire. La clé est donc rendue lisible plutôt
    /// qu'affichée brute — seule sa ponctuation change, rien n'est deviné.
    ///
    /// Les règles d'alarme reçoivent les mêmes clés dans leur champ `name` : elles
    /// s'appuient sur cette conversion plutôt que d'en écrire une seconde.
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

    /// Le détail des processus d'un groupe n'est pas exploité : seul leur nombre l'est.
    private struct AnyDecodableProcess: nonisolated Decodable, Sendable {}
}
