//
//  DSMAccount.swift
//  dsmaccess
//
//  Comptes et groupes locaux exposés par SYNO.Core.User et SYNO.Core.Group.
//

import Foundation

struct DSMUser: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let description: String?
    let email: String?
    let uid: Int?
    let expiration: String?
    let groups: [String]
    let isAdministrator: Bool

    var id: String { name }

    var isDisabled: Bool {
        guard let expiration else { return false }
        return ["now", "expired", "disabled", "true"].contains(expiration.lowercased())
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description = "desc"
        case alternateDescription = "description"
        case email
        case uid
        case expiration = "expired"
        case groups
        case admin
        case isAdmin = "is_admin"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        description = values.flexString(.description) ?? values.flexString(.alternateDescription)
        email = values.flexString(.email)
        uid = values.flexInt(.uid)
        expiration = values.flexString(.expiration)
        groups = try values.decodeIfPresent([String].self, forKey: .groups) ?? []
        isAdministrator = values.flexBool(.admin) ?? values.flexBool(.isAdmin) ?? groups.contains("administrators")
    }
}

struct DSMGroup: nonisolated Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let description: String?
    let gid: Int?
    var members: [String]

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case description = "desc"
        case alternateDescription = "description"
        case gid
        case users
        case members
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.requiredFlexString(.name)
        description = values.flexString(.description) ?? values.flexString(.alternateDescription)
        gid = values.flexInt(.gid)
        members = try values.decodeArray(String.self, forFirstPresent: [.users, .members])
    }
}

struct DSMUserList: nonisolated Decodable, Sendable {
    let users: [DSMUser]

    enum CodingKeys: String, CodingKey { case users }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        users = try values.decodeIfPresent([DSMUser].self, forKey: .users) ?? []
    }
}

/// Réponse de `SYNO.Core.Group.Member list` : les comptes appartenant à un groupe.
struct DSMGroupMemberList: nonisolated Decodable, Sendable {
    let names: [String]

    enum CodingKeys: String, CodingKey { case users }

    private struct Member: nonisolated Decodable {
        let name: String
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let users = try values.decodeIfPresent([Member].self, forKey: .users) ?? []
        names = users.map(\.name)
    }
}

struct DSMGroupList: nonisolated Decodable, Sendable {
    let groups: [DSMGroup]

    enum CodingKeys: String, CodingKey { case groups }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        groups = try values.decodeIfPresent([DSMGroup].self, forKey: .groups) ?? []
    }
}

/// Règles de mot de passe imposées par le NAS (`SYNO.Core.User.PasswordPolicy`).
/// DSM refuse une création ou un changement non conforme sans dire laquelle est en cause :
/// l'app les énonce donc avant la saisie.
struct DSMPasswordPolicy: nonisolated Decodable, Equatable, Sendable {
    let minimumLength: Int?
    let requiresMixedCase: Bool
    let requiresDigit: Bool
    let requiresSpecialCharacter: Bool
    let excludesUserName: Bool
    let excludesCommonPasswords: Bool

    var hasRequirements: Bool { !requirements.isEmpty }

    /// Une phrase complète par règle active, dans l'ordre où DSM les présente.
    var requirements: [String] {
        var rules: [String] = []
        if let minimumLength {
            rules.append(String(localized: "Au moins \(minimumLength) caractères."))
        }
        if requiresMixedCase {
            rules.append(String(localized: "Des majuscules et des minuscules."))
        }
        if requiresDigit {
            rules.append(String(localized: "Au moins un chiffre."))
        }
        if requiresSpecialCharacter {
            rules.append(String(localized: "Au moins un caractère spécial."))
        }
        if excludesUserName {
            rules.append(String(localized: "Ni le nom ni la description du compte."))
        }
        if excludesCommonPasswords {
            rules.append(String(localized: "Pas un mot de passe courant."))
        }
        return rules
    }

    /// Mot de passe aléatoire respectant les règles connues du NAS, ou des règles saines
    /// quand il ne les expose pas. Les caractères qui se confondent à la lecture et à
    /// l'écoute (l, 1, I, O, 0) sont exclus : ce mot de passe est fait pour être relu,
    /// dicté ou recopié.
    static func generatedPassword(for policy: DSMPasswordPolicy?) -> String {
        let lowercase = Array("abcdefghijkmnpqrstuvwxyz")
        let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        let digits = Array("23456789")
        let specials = Array("!@#$%*-_=+")

        var required: [[Character]] = [lowercase, uppercase, digits]
        if policy?.requiresSpecialCharacter == true {
            required.append(specials)
        }
        let alphabet = required.flatMap { $0 }
        let length = max(16, policy?.minimumLength ?? 0)

        // Une occurrence garantie par classe exigée, le reste tiré dans l'alphabet complet.
        var characters = required.map { $0.randomElement()! }
        while characters.count < length {
            characters.append(alphabet.randomElement()!)
        }
        return String(characters.shuffled())
    }

    enum CodingKeys: String, CodingKey {
        case strongPassword = "strong_password"
    }

    enum RuleKeys: String, CodingKey {
        case minLength = "min_length"
        case minLengthEnable = "min_length_enable"
        case mixedCase = "mixed_case"
        case includedNumericChar = "included_numeric_char"
        case includedSpecialChar = "included_special_char"
        case excludeUsername = "exclude_username"
        case excludeCommonPassword = "exclude_common_password"
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rules = try values.nestedContainer(keyedBy: RuleKeys.self, forKey: .strongPassword)
        // DSM conserve « min_length » même quand la règle est désactivée : c'est le drapeau
        // qui décide, pas la valeur.
        let lengthEnabled = rules.flexBool(.minLengthEnable) ?? false
        minimumLength = lengthEnabled ? rules.flexInt(.minLength) : nil
        requiresMixedCase = rules.flexBool(.mixedCase) ?? false
        requiresDigit = rules.flexBool(.includedNumericChar) ?? false
        requiresSpecialCharacter = rules.flexBool(.includedSpecialChar) ?? false
        excludesUserName = rules.flexBool(.excludeUsername) ?? false
        excludesCommonPasswords = rules.flexBool(.excludeCommonPassword) ?? false
    }
}

struct DSMUserDraft: Sendable {
    let name: String
    let password: String
    let description: String
    let email: String
    let groups: [String]
}

struct DSMGroupDraft: Sendable {
    let name: String
    let description: String
}
