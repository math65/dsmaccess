//
//  LoginActivityEvent.swift
//  dsmaccess
//
//  Activité de connexion relevée par le Conseiller de sécurité
//  (SYNO.SecurityAdvisor.LoginActivity list).
//
//  ⚠️ Le NAS ne renvoie pas de phrase : il renvoie une **clé de son catalogue**
//  (`str_section` + `str_id`) et un sac d'arguments (`str_args`) que son client web assemble
//  lui-même. Les phrases sont donc rédigées ici, clé par clé, et une clé inconnue est signalée
//  comme telle plutôt que rendue par un texte inventé.
//
//  Contrat relevé sur DSM 7.4 le 30/07/2026, sur les deux seules clés que ce NAS a produites :
//  `loganalyzer:abnormal_login` et `loganalyzer:brute_force_attack`.
//

import Foundation

struct LoginActivityPage: nonisolated Decodable, Sendable {
    let events: [LoginActivityEvent]
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case items, total
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decodeIfPresent([LoginActivityEvent].self, forKey: .items) ?? []
        // Le NAS n'attribue pas d'identifiant : le rang distingue deux alertes identiques.
        events = decoded.enumerated().map { offset, event in
            var positioned = event
            positioned.position = offset
            return positioned
        }
        total = c.flexInt(.total)
    }
}

struct LoginActivityEvent: nonisolated Decodable, Sendable, Identifiable {
    fileprivate(set) var position = 0
    /// Horodatage brut, au format « aaaa/MM/jj HH:mm:ss ».
    let rawTime: String?
    let severity: Severity
    /// Compte concerné, tel que le NAS le nomme hors des arguments.
    let account: String?
    let kind: Kind
    let details: Details

    var id: Int { position }

    var recordedAt: Date? {
        guard let rawTime else { return nil }
        return Self.nasFormatter.date(from: rawTime)
    }

    var sortableDate: Date { recordedAt ?? .distantPast }
    var sortableAccount: String { account ?? details.user ?? "" }
    /// Trié par gravité décroissante, et non par ordre alphabétique.
    var sortableSeverity: Int { severity.rank }

    enum Severity: nonisolated Sendable, Equatable, Hashable {
        case low
        case medium
        case high
        case other(String)

        var rank: Int {
            switch self {
            case .low: 0
            case .other: 1
            case .medium: 2
            case .high: 3
            }
        }

        nonisolated init(rawValue: String?) {
            switch rawValue?.lowercased() {
            case "low": self = .low
            case "medium": self = .medium
            case "high", "critical": self = .high
            case let value?: self = .other(value)
            case nil: self = .other("")
            }
        }
    }

    /// Nature de l'alerte, désignée par la clé du catalogue DSM. Une clé que nous ne savons pas
    /// rédiger est conservée telle quelle : l'écran dira qu'il ne sait pas la formuler plutôt
    /// que d'inventer une phrase.
    enum Kind: nonisolated Sendable, Equatable, Hashable {
        case abnormalLogin
        case bruteForceAttack
        case unknown(section: String, identifier: String)

        nonisolated init(section: String?, identifier: String?) {
            switch (section?.lowercased(), identifier?.lowercased()) {
            case ("loganalyzer", "abnormal_login"): self = .abnormalLogin
            case ("loganalyzer", "brute_force_attack"): self = .bruteForceAttack
            default:
                self = .unknown(section: section ?? "", identifier: identifier ?? "")
            }
        }
    }

    /// Arguments que le NAS joint à la clé. Tous optionnels : ils diffèrent d'une clé à l'autre,
    /// et une clé future en apporterait d'autres.
    struct Details: nonisolated Decodable, Sendable, Equatable {
        let user: String?
        /// Adresse d'origine, pour une connexion inhabituelle.
        let address: String?
        /// Adresses d'origine, pour une attaque par force brute.
        let addresses: [String]
        let city: String?
        let countryCode: String?
        let protocolName: String?
        let protocolNames: [String]
        let attemptCount: Int?
        let thresholdMinutes: Int?
        let userAgent: String?

        enum CodingKeys: String, CodingKey {
            case user, ip, city, protocol_name = "protocol"
            case countryCode = "country_code"
            case addresses = "src_ip_list"
            case protocolNames = "protocol_list"
            case attemptCount = "attempt_count"
            case thresholdMinutes = "thresh_minutes"
            case userAgent = "user_agent"
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            user = Self.meaningful(c.flexString(.user))
            address = Self.meaningful(c.flexString(.ip))
            addresses = (try? c.decode([String].self, forKey: .addresses)) ?? []
            city = Self.meaningful(c.flexString(.city))
            countryCode = Self.meaningful(c.flexString(.countryCode))
            protocolName = Self.meaningful(c.flexString(.protocol_name))
            protocolNames = (try? c.decode([String].self, forKey: .protocolNames)) ?? []
            attemptCount = c.flexInt(.attemptCount)
            thresholdMinutes = c.flexInt(.thresholdMinutes)
            userAgent = Self.meaningful(c.flexString(.userAgent))
        }

        /// Toutes les adresses connues de l'événement, quelle que soit la clé qui les porte.
        var allAddresses: [String] {
            if !addresses.isEmpty { return addresses }
            return [address].compactMap { $0 }
        }

        nonisolated private static func meaningful(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }

        /// Détails vides, pour un événement dont le NAS n'a joint aucun argument.
        nonisolated static let empty = Details()

        nonisolated private init() {
            user = nil
            address = nil
            addresses = []
            city = nil
            countryCode = nil
            protocolName = nil
            protocolNames = []
            attemptCount = nil
            thresholdMinutes = nil
            userAgent = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case severity, user
        case rawTime = "create_time"
        case section = "str_section"
        case identifier = "str_id"
        case arguments = "str_args"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rawTime = c.flexString(.rawTime)
        severity = Severity(rawValue: c.flexString(.severity))
        account = c.flexString(.user).flatMap { $0.isEmpty ? nil : $0 }
        kind = Kind(
            section: c.flexString(.section),
            identifier: c.flexString(.identifier)
        )
        // Les arguments changent d'une clé à l'autre : leur absence n'empêche pas de lister
        // l'alerte, elle prive seulement la phrase de ses précisions.
        details = (try? c.decode(Details.self, forKey: .arguments)) ?? Details.empty
    }

    private static let nasFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/M/d H:m:s"
        return formatter
    }()
}
