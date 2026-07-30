//
//  SystemLogEntry.swift
//  dsmaccess
//
//  Journal système du NAS (SYNO.Core.SyslogClient.Log list) et liste de blocage du blocage
//  automatique (SYNO.Core.Security.AutoBlock.Rules list).
//
//  Contrats relevés sur DSM 7.4 le 30/07/2026. Quatre particularités :
//  — Le journal arrive sous la clé `items`, et chaque page porte le décompte par gravité.
//    ⚠️ Ces décomptes valent pour la page reçue, pas pour tout le journal du NAS.
//  — La catégorie tient dans `logtype`, que le NAS a **déjà traduit** dans la langue du compte
//    DSM, et dans `orginalLogType` (sic), qui garde la valeur technique. C'est celle-ci qui est
//    lue, pour que l'app parle sa propre langue et non celle de la session DSM.
//  — Une entrée ne comporte **aucune adresse d'origine** : ni `from`, ni `ip`.
//  — Une adresse bloquée sans expiration porte `expire_date` à 0, que le NAS formate quand même
//    en « 1970/01/01 » : c'est l'entier qui fait foi.
//

import Foundation

struct SystemLogPage: nonisolated Decodable, Sendable {
    let entries: [SystemLogEntry]
    /// Nombre d'entrées que le NAS conserve, indépendant de la page demandée.
    let total: Int?
    /// Décomptes par gravité **de la page reçue**, renvoyés par le NAS avec celle-ci.
    let errorCount: Int?
    let warningCount: Int?
    let infoCount: Int?

    enum CodingKeys: String, CodingKey {
        case items, total
        case errorCount = "errorCount"
        case warningCount = "warnCount"
        case infoCount = "infoCount"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([SystemLogEntry].self, forKey: .items) ?? []
        // Le NAS n'attribue pas d'identifiant et deux entrées peuvent partager la seconde, le
        // niveau et le message : le rang dans la page est la seule identité qui les distingue.
        entries = decoded.enumerated().map { offset, entry in
            var positioned = entry
            positioned.position = offset
            return positioned
        }
        total = c.flexInt(.total)
        errorCount = c.flexInt(.errorCount)
        warningCount = c.flexInt(.warningCount)
        infoCount = c.flexInt(.infoCount)
    }
}

struct SystemLogEntry: nonisolated Decodable, Sendable, Identifiable {
    /// Rang dans la page renvoyée, attribué au décodage. Le NAS ne fournit pas de clé.
    fileprivate(set) var position = 0
    /// Horodatage brut du NAS, au format « aaaa/MM/jj HH:mm:ss ».
    let rawTime: String?
    let level: Level
    /// Catégorie technique, non traduite : « system ». Sert de clé d'affichage.
    let technicalCategory: String?
    /// Catégorie telle que le NAS l'a traduite, dans la langue du compte DSM. Repli quand la
    /// valeur technique est inconnue de l'app.
    let translatedCategory: String?
    /// Compte concerné par l'événement, quand il y en a un.
    let account: String?
    let message: String

    var id: Int { position }

    /// Renumérote l'entrée à partir du rang donné. Les pages suivantes du journal repartent de
    /// zéro : sans ce décalage, la deuxième page porterait les identifiants de la première et
    /// le tableau confondrait ses lignes.
    nonisolated func renumbered(from start: Int) -> SystemLogEntry {
        var copy = self
        copy.position += start
        return copy
    }

    /// Horodatage rendu dans la langue et le fuseau du Mac. DSM n'indique pas le fuseau de sa
    /// valeur : elle est lue comme locale, ce qui est juste tant que le NAS et le Mac partagent
    /// le même.
    var recordedAt: Date? {
        guard let rawTime else { return nil }
        return Self.nasFormatter.date(from: rawTime)
    }

    /// Clés de tri non optionnelles : une valeur absente se range en tête plutôt que
    /// d'empêcher le tri de sa colonne.
    var sortableDate: Date { recordedAt ?? .distantPast }
    var sortableAccount: String { account ?? "" }
    var sortableMessage: String { message }
    /// Trié par gravité décroissante, et non par ordre alphabétique.
    var sortableLevel: Int { level.severity }

    /// Gravité telle que DSM la code : trois valeurs courtes. Une quatrième serait une
    /// évolution de DSM, conservée telle quelle plutôt que rangée d'office dans l'une d'elles.
    enum Level: nonisolated Sendable, Equatable, Hashable {
        case info
        case warning
        case error
        case other(String)

        var severity: Int {
            switch self {
            case .info: 0
            case .other: 1
            case .warning: 2
            case .error: 3
            }
        }

        nonisolated init(rawValue: String?) {
            switch rawValue?.lowercased() {
            case "info", "information": self = .info
            case "warn", "warning": self = .warning
            case "err", "error", "crit", "critical": self = .error
            case let value?: self = .other(value)
            case nil: self = .other("")
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case time, level, logtype, who
        case technicalCategory = "orginalLogType"
        case message = "descr"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawTime = c.flexString(.time)
        level = Level(rawValue: c.flexString(.level))
        technicalCategory = c.flexString(.technicalCategory).flatMap { $0.isEmpty ? nil : $0 }
        translatedCategory = c.flexString(.logtype).flatMap { $0.isEmpty ? nil : $0 }
        account = c.flexString(.who).flatMap { $0.isEmpty ? nil : $0 }
        message = c.flexString(.message) ?? ""
    }

    private static let nasFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Composantes à un chiffre acceptées comme complétées : cette API envoie des valeurs
        // complétées, mais le client web de DSM lit les deux formes.
        formatter.dateFormat = "yyyy/M/d H:m:s"
        return formatter
    }()
}

/// Une adresse de la liste de blocage du blocage automatique.
struct BlockedAddress: nonisolated Decodable, Sendable, Identifiable {
    let address: String
    /// Pays déduit par DSM. Vide quand la géolocalisation n'aboutit pas.
    let country: String?
    let isPublic: Bool
    let blockedAt: Date?
    /// `nil` quand le blocage n'expire pas. Le NAS envoie alors 0, qu'il formate lui-même en
    /// 1970 : la date formatée n'est donc jamais lue.
    let expiresAt: Date?

    var id: String { address }

    var sortableCountry: String { country ?? "" }
    var sortableBlockedAt: Date { blockedAt ?? .distantPast }
    /// Un blocage sans expiration se range après les autres : il est le plus durable.
    var sortableExpiry: Date { expiresAt ?? .distantFuture }

    enum CodingKeys: String, CodingKey {
        case ip, country
        case isPublic = "is_public_ip"
        case blockedAt = "record_date"
        case expiresAt = "expire_date"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.requiredFlexString(.ip)
        country = c.flexString(.country).flatMap { $0.isEmpty ? nil : $0 }
        isPublic = c.flexBool(.isPublic) ?? false
        blockedAt = c.flexInt64(.blockedAt).flatMap(Self.date)
        expiresAt = c.flexInt64(.expiresAt).flatMap(Self.date)
    }

    /// Zéro n'est pas une date : c'est la façon dont DSM dit « pas d'expiration », et pour
    /// `record_date` l'absence de valeur.
    nonisolated private static func date(_ timestamp: Int64) -> Date? {
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

struct BlockedAddressPage: nonisolated Decodable, Sendable {
    let addresses: [BlockedAddress]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case addresses = "ip_info"
        case total
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addresses = try c.decodeIfPresent([BlockedAddress].self, forKey: .addresses) ?? []
        total = c.flexInt(.total)
    }
}
