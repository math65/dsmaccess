//
//  LoginActivityEvent.swift
//  dsmaccess
//
//  Login activity reported by Security Advisor
//  (SYNO.SecurityAdvisor.LoginActivity list).
//
//  ⚠️ The NAS does not return a sentence: it returns a **key from its own catalog**
//  (`str_section` + `str_id`) and a bag of arguments (`str_args`) that its web client
//  assembles itself. The sentences are therefore written here, key by key, and an unknown key
//  is reported as such rather than rendered with invented text.
//
//  Contract captured on DSM 7.4 on 2026/07/30, on the only two keys this NAS produced:
//  `loganalyzer:abnormal_login` and `loganalyzer:brute_force_attack`.
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
        // The NAS assigns no identifier: the rank distinguishes two identical alerts.
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
    /// Raw timestamp, in "yyyy/MM/dd HH:mm:ss" format.
    let rawTime: String?
    let severity: Severity
    /// Account involved, as the NAS names it outside the arguments.
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
    /// Sorted by decreasing severity, not alphabetically.
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

    /// Nature of the alert, designated by the DSM catalog key. A key we do not know how to
    /// word is kept as is: the screen will say it cannot phrase it rather than invent a
    /// sentence.
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

    /// Arguments the NAS attaches to the key. All optional: they differ from one key to the
    /// next, and a future key would bring others.
    struct Details: nonisolated Decodable, Sendable, Equatable {
        let user: String?
        /// Source address, for an unusual sign-in.
        let address: String?
        /// Source addresses, for a brute-force attack.
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

        /// Every address known for the event, whichever key carries it.
        var allAddresses: [String] {
            if !addresses.isEmpty { return addresses }
            return [address].compactMap { $0 }
        }

        nonisolated private static func meaningful(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }

        /// Empty details, for an event the NAS attached no argument to.
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
        // The arguments change from one key to the next: their absence does not prevent
        // listing the alert, it only deprives the sentence of its details.
        details = (try? c.decode(Details.self, forKey: .arguments)) ?? Details.empty
    }

    private static let nasFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/M/d H:m:s"
        return formatter
    }()
}
