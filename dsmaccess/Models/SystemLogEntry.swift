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

/// Journal demandé au NAS. ⚠️ `SYNO.Core.SyslogClient.Log` ne tient pas un journal mais
/// plusieurs, et sans `logtype` il ne renvoie que celui du système : sur le DS920+ de
/// développement, 6 997 entrées système contre plus de 114 000 au total. La valeur brute est
/// celle que le NAS attend, et les journaux de transfert portent le nom de leur protocole.
enum SystemLogKind: String, nonisolated Sendable, Hashable, Identifiable, CaseIterable {
    case system
    case connection
    case afp
    case cifs
    case fileStation = "filestation"
    case ftp
    case tftp
    case webdav

    var id: String { rawValue }

    /// Journaux que le NAS tient toujours, sans réglage à activer.
    static let always: [SystemLogKind] = [.system, .connection]

    /// Journaux de transfert, chacun conditionné par la journalisation de son protocole.
    static let transfers: [SystemLogKind] = [.afp, .cifs, .fileStation, .ftp, .tftp, .webdav]

    /// Les journaux de transfert n'ont pas la même forme que les autres : pas de gravité, mais
    /// l'adresse d'origine, l'opération et la taille du fichier. Les colonnes en dépendent.
    var isTransfer: Bool { Self.transfers.contains(self) }
}

/// Format d'export proposé par le NAS. La valeur brute est celle qu'il attend.
enum SystemLogExportFormat: String, nonisolated Sendable, CaseIterable, Identifiable {
    case csv
    case html

    var id: String { rawValue }

    /// Extension du fichier proposé à l'enregistrement.
    var fileExtension: String { rawValue }
}

/// Protocoles dont le NAS journalise les transferts (SYNO.Core.SyslogClient.FileTransfer get).
/// Ce réglage décide quels journaux de transfert existent : demander un journal désactivé
/// renvoie zéro entrée sans erreur, ce qui se lirait comme un journal vide.
struct FileTransferLogging: nonisolated Decodable, Sendable {
    let enabled: Set<SystemLogKind>

    enum CodingKeys: String, CodingKey {
        case afp, cifs, filestation, ftp, tftp, webdav
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var active: Set<SystemLogKind> = []
        let flags: [(CodingKeys, SystemLogKind)] = [
            (.afp, .afp), (.cifs, .cifs), (.filestation, .fileStation),
            (.ftp, .ftp), (.tftp, .tftp), (.webdav, .webdav),
        ]
        for (key, kind) in flags where c.flexBool(key) == true {
            active.insert(kind)
        }
        enabled = active
    }
}

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
    /// `nil` dans les journaux de transfert, qui n'attribuent aucune gravité. Une colonne
    /// « niveau inconnu » y serait un contresens.
    let level: Level?
    /// Catégorie technique, non traduite : « system ». Sert de clé d'affichage.
    let technicalCategory: String?
    /// Catégorie telle que le NAS l'a traduite, dans la langue du compte DSM. Repli quand la
    /// valeur technique est inconnue de l'app.
    let translatedCategory: String?
    /// Compte concerné. Le journal système et celui des connexions l'écrivent dans `who`, les
    /// journaux de transfert dans `username`.
    let account: String?
    let message: String
    /// Adresse d'origine, présente dans les journaux de transfert seulement.
    let address: String?
    /// Opération enregistrée par un journal de transfert : lecture, écriture, suppression…
    let operation: String?
    /// Taille du fichier transféré, en octets. `nil` pour un dossier ou hors transfert.
    let fileSize: Int64?
    /// Vrai quand l'entrée porte sur un dossier et non un fichier.
    let isDirectory: Bool

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
    var sortableAddress: String { address ?? "" }
    var sortableOperation: String { operation ?? "" }
    /// Une entrée sans taille se range avant les autres plutôt que d'empêcher le tri.
    var sortableSize: Int64 { fileSize ?? -1 }
    /// Trié par gravité décroissante, et non par ordre alphabétique. Une entrée sans gravité se
    /// range avant les informations.
    var sortableLevel: Int { level?.severity ?? -1 }

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
        case time, level, logtype, who, username, ip, cmd, filesize, isdir
        case technicalCategory = "orginalLogType"
        case message = "descr"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawTime = c.flexString(.time)
        // Absent des journaux de transfert : une gravité inventée y serait fausse.
        level = c.flexString(.level).map { Level(rawValue: $0) }
        technicalCategory = c.flexString(.technicalCategory).flatMap { $0.isEmpty ? nil : $0 }
        translatedCategory = c.flexString(.logtype).flatMap { $0.isEmpty ? nil : $0 }
        account = Self.meaningful(c.flexString(.who) ?? c.flexString(.username))
        message = c.flexString(.message) ?? ""
        address = Self.meaningful(c.flexString(.ip))
        operation = Self.meaningful(c.flexString(.cmd))
        // Un dossier n'a pas de taille utile, et le NAS y écrit zéro.
        isDirectory = c.flexBool(.isdir) ?? false
        fileSize = isDirectory ? nil : c.flexInt64(.filesize).flatMap { $0 > 0 ? $0 : nil }
    }

    nonisolated private static func meaningful(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "-" ? nil : trimmed
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
