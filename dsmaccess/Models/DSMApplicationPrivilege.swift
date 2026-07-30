//
//  DSMApplicationPrivilege.swift
//  dsmaccess
//
//  Access rights to the DSM applications (SYNO.Core.AppPriv).
//

import Foundation

/// Explicit decision carried by a rule. Its absence leaves the application governed by the
/// right granted to everyone, then by the default declared by the application itself.
enum DSMApplicationDecision: String, Sendable, Hashable, CaseIterable, Identifiable {
    case allow
    case deny

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allow: return String(localized: "privileges.application.allow")
        case .deny: return String(localized: "privileges.application.deny")
        }
    }
}

/// An application from the catalogue, together with the decision made for an account or group.
struct DSMApplicationPrivilege: Identifiable, Hashable, Sendable {
    let appID: String
    /// Name already localized by DSM: do not translate it again.
    let name: String
    let isGrantedByDefault: Bool
    var decision: DSMApplicationDecision?
    /// True when the rule targets specific addresses rather than "all". The app cannot edit
    /// that case without risking erasing the restriction: the row stays read-only.
    let restrictsAddresses: Bool

    var id: String { appID }

    /// What applies in the absence of an explicit decision, to be stated so that "by default"
    /// is not a blind choice.
    var fallbackLabel: String {
        isGrantedByDefault
            ? String(localized: "privileges.application.allow_default")
            : String(localized: "privileges.application.deny_default")
    }
}

/// Catalogue of the applications subject to authorization (`SYNO.Core.AppPriv.App list`).
struct DSMApplicationList: nonisolated Decodable, Sendable {
    struct Application: nonisolated Decodable, Sendable {
        let appID: String
        let name: String
        let isGrantedByDefault: Bool

        enum CodingKeys: String, CodingKey {
            case appID = "app_id"
            case name
            case grantByDefault = "grant_by_default"
        }

        nonisolated init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            appID = try values.requiredFlexString(.appID)
            name = values.flexString(.name) ?? appID
            isGrantedByDefault = values.flexBool(.grantByDefault) ?? false
        }
    }

    let applications: [Application]

    enum CodingKeys: String, CodingKey { case applications }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        applications = try values.decodeIfPresent([Application].self, forKey: .applications) ?? []
    }
}

/// Rules set for an entity (`SYNO.Core.AppPriv.Rule get`). DSM expresses the decision through
/// two address lists: "0.0.0.0" means "all" there.
struct DSMApplicationRuleList: nonisolated Decodable, Sendable {
    struct Rule: nonisolated Decodable, Sendable {
        static let anyAddress = "0.0.0.0"

        let appID: String
        let allowedAddresses: [String]
        let deniedAddresses: [String]

        var decision: DSMApplicationDecision? {
            if !deniedAddresses.isEmpty { return .deny }
            if !allowedAddresses.isEmpty { return .allow }
            return nil
        }

        var restrictsAddresses: Bool {
            (allowedAddresses + deniedAddresses).contains { $0 != Self.anyAddress }
        }

        enum CodingKeys: String, CodingKey {
            case appID = "app_id"
            case allowIP = "allow_ip"
            case denyIP = "deny_ip"
        }

        nonisolated init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            appID = try values.requiredFlexString(.appID)
            allowedAddresses = try values.decodeIfPresent([String].self, forKey: .allowIP) ?? []
            deniedAddresses = try values.decodeIfPresent([String].self, forKey: .denyIP) ?? []
        }
    }

    let rules: [Rule]

    enum CodingKeys: String, CodingKey { case rules }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rules = try values.decodeIfPresent([Rule].self, forKey: .rules) ?? []
    }
}
