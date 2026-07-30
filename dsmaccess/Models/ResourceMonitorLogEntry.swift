//
//  ResourceMonitorLogEntry.swift
//  dsmaccess
//
//  Historique du moniteur de ressources (SYNO.ResourceMonitor.Log list) : les alertes que le
//  NAS a enregistrées quand une ressource a franchi un seuil.
//
//  Deux particularités relevées sur DSM 7.4 :
//  — `time` n'est **pas** complété à deux chiffres, à la différence de `CurrentConnection` :
//    le client web le lit avec « Y/n/j G:i:s », donc « 2026/7/30 9:05:12 » est une valeur
//    normale. Un format rigide en « aaaa/MM/jj » ne la reconnaîtrait pas.
//  — `level` arrive en anglais dans la charge utile ; c'est le client qui traduit. Affiché
//    tel quel, l'écran parlerait anglais à un utilisateur français.
//

import Foundation

/// Réglages du moniteur de ressources (SYNO.ResourceMonitor.Setting get). DSM n'en expose
/// qu'un : l'enregistrement de l'historique. Sans lui, le journal reste vide indéfiniment.
struct ResourceMonitorSetting: nonisolated Decodable, Sendable {
    let historyEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case historyEnabled = "enable_history"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        historyEnabled = try c.requiredFlexBool(.historyEnabled)
    }
}

/// Nombre de règles d'alarme définies (SYNO.ResourceMonitor.EventRule list). Le journal ne se
/// remplit que lorsqu'une règle est franchie : sans règle, il reste vide quoi qu'il arrive.
/// L'écran Historique n'a besoin que de ce compte ; la forme complète d'une règle appartient
/// à l'écran d'alarme.
struct ResourceMonitorAlarmRuleCount: nonisolated Decodable, Sendable {
    let total: Int

    enum CodingKeys: String, CodingKey {
        case rules, total
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let announced = c.flexInt(.total) {
            total = announced
        } else {
            // Le NAS annonce toujours `total`, mais le compte des règles reçues reste juste
            // si une version le laissait tomber.
            total = (try? c.decodeIfPresent([AnyRule].self, forKey: .rules))??.count ?? 0
        }
    }

    /// Les champs d'une règle ne sont pas lus ici : seul le nombre d'éléments compte.
    private struct AnyRule: nonisolated Decodable, Sendable {
        nonisolated init(from decoder: Decoder) throws { }
    }
}

struct ResourceMonitorLogPage: nonisolated Decodable, Sendable {
    let entries: [ResourceMonitorLogEntry]
    /// Nombre total d'entrées conservées par le NAS, indépendant de la page demandée.
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case logs, total
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([ResourceMonitorLogEntry].self, forKey: .logs) ?? []
        // Le NAS n'attribue aucun identifiant et deux alertes identiques peuvent tomber dans
        // la même seconde : le rang dans la page est la seule identité qui les distingue.
        entries = decoded.enumerated().map { offset, entry in
            var positioned = entry
            positioned.position = offset
            return positioned
        }
        total = c.flexInt(.total)
    }
}

struct ResourceMonitorLogEntry: nonisolated Decodable, Sendable, Identifiable {
    /// Rang dans la page renvoyée, attribué au décodage. Le NAS ne fournit pas de clé.
    fileprivate(set) var position = 0
    /// Horodatage brut du NAS, dont les composantes ne sont pas complétées à deux chiffres.
    let rawTime: String?
    let level: Level
    /// Description de l'alerte, telle que le NAS l'a écrite.
    let event: String?

    var id: Int { position }

    /// Horodatage rendu dans la langue et le fuseau du Mac. DSM n'indique pas le fuseau de sa
    /// valeur : elle est lue comme locale, ce qui est juste tant que le NAS et le Mac
    /// partagent le même. La chaîne brute sert de repli plutôt que de n'afficher rien.
    var recordedAt: Date? {
        guard let rawTime else { return nil }
        return Self.nasFormatter.date(from: rawTime)
    }

    /// Clés de tri non optionnelles : une valeur absente se range en tête plutôt que
    /// d'empêcher le tri de sa colonne.
    var sortableDate: Date { recordedAt ?? .distantPast }
    var sortableEvent: String { event ?? "" }
    /// Trié par gravité décroissante et non par ordre alphabétique : classer « Critique »
    /// après « Information » n'aurait aucun sens pour l'utilisateur.
    var sortableLevel: Int { level.severity }

    /// Gravité de l'alerte. DSM n'en connaît que trois ; une quatrième valeur serait une
    /// évolution de DSM, conservée telle quelle plutôt que rangée d'office dans l'une d'elles.
    enum Level: nonisolated Sendable, Equatable {
        case information
        case warning
        case critical
        case other(String)

        /// Ordre de gravité croissant, pour le tri de la colonne.
        var severity: Int {
            switch self {
            case .information: 0
            case .other: 1
            case .warning: 2
            case .critical: 3
            }
        }

        nonisolated init(rawValue: String?) {
            switch rawValue?.lowercased() {
            case "information", "info": self = .information
            case "warning", "warn": self = .warning
            case "critical", "error": self = .critical
            case let value?: self = .other(value)
            case nil: self = .other("")
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case time, level, event
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawTime = c.flexString(.time)
        level = Level(rawValue: c.flexString(.level))
        event = c.flexString(.event).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Composantes à un chiffre dans le motif : DateFormatter accepte alors les deux formes,
    /// complétée ou non. `CurrentConnection` reçoit un horodatage complété et emploie un motif
    /// rigide ; les deux API du même module ne s'écrivent pas de la même façon.
    private static let nasFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/M/d H:m:s"
        return formatter
    }()
}
