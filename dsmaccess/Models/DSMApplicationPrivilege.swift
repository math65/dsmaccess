//
//  DSMApplicationPrivilege.swift
//  dsmaccess
//
//  Droits d'accès aux applications DSM (SYNO.Core.AppPriv).
//

import Foundation

/// Décision explicite portée par une règle. Son absence laisse l'application relever du
/// droit accordé à tout le monde, puis du défaut déclaré par l'application elle-même.
enum DSMApplicationDecision: String, Sendable, Hashable, CaseIterable, Identifiable {
    case allow
    case deny

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allow: return String(localized: "Autoriser")
        case .deny: return String(localized: "Refuser")
        }
    }
}

/// Une application du catalogue, accompagnée de la décision prise pour un compte ou un groupe.
struct DSMApplicationPrivilege: Identifiable, Hashable, Sendable {
    let appID: String
    /// Nom déjà localisé par DSM : ne pas le retraduire.
    let name: String
    let isGrantedByDefault: Bool
    var decision: DSMApplicationDecision?
    /// Vrai quand la règle vise des adresses précises plutôt que « toutes ». L'app ne sait
    /// pas éditer ce cas sans risquer d'effacer la restriction : la ligne reste en lecture.
    let restrictsAddresses: Bool

    var id: String { appID }

    /// Ce qui s'applique faute de décision explicite, à énoncer pour que « par défaut » ne
    /// soit pas un choix aveugle.
    var fallbackLabel: String {
        isGrantedByDefault
            ? String(localized: "autorisée par défaut")
            : String(localized: "refusée par défaut")
    }
}

/// Catalogue des applications soumises à autorisation (`SYNO.Core.AppPriv.App list`).
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

/// Règles posées pour une entité (`SYNO.Core.AppPriv.Rule get`). DSM exprime la décision par
/// deux listes d'adresses : « 0.0.0.0 » y signifie « toutes ».
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
