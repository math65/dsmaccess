//
//  DSMAccount.swift
//  dsmaccess
//
//  Local accounts and groups exposed by SYNO.Core.User and SYNO.Core.Group.
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

/// Response of `SYNO.Core.Group.Member list`: the accounts belonging to a group.
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

/// Password rules enforced by the NAS (`SYNO.Core.User.PasswordPolicy`).
/// DSM rejects a non-compliant creation or change without saying which rule is at fault, so
/// the app states them before the user types.
struct DSMPasswordPolicy: nonisolated Decodable, Equatable, Sendable {
    let minimumLength: Int?
    let requiresMixedCase: Bool
    let requiresDigit: Bool
    let requiresSpecialCharacter: Bool
    let excludesUserName: Bool
    let excludesCommonPasswords: Bool

    var hasRequirements: Bool { !requirements.isEmpty }

    /// One complete sentence per active rule, in the order DSM presents them.
    var requirements: [String] {
        var rules: [String] = []
        if let minimumLength {
            rules.append(String(localized: "account.password_rule.min_length", defaultValue: "At least \(minimumLength) characters."))
        }
        if requiresMixedCase {
            rules.append(String(localized: "account.password_rule.mixed_case"))
        }
        if requiresDigit {
            rules.append(String(localized: "account.password_rule.digit"))
        }
        if requiresSpecialCharacter {
            rules.append(String(localized: "account.password_rule.special_character"))
        }
        if excludesUserName {
            rules.append(String(localized: "account.password_rule.exclude_account_info"))
        }
        if excludesCommonPasswords {
            rules.append(String(localized: "account.password_rule.not_common"))
        }
        return rules
    }

    /// Random password meeting the NAS's known rules, or sane rules when it does not expose
    /// them. Characters that are easy to confuse when read and when heard (l, 1, I, O, 0) are
    /// excluded: this password is meant to be re-read, dictated or copied out.
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

        // One guaranteed occurrence per required class, the rest drawn from the full alphabet.
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
        // DSM keeps "min_length" even when the rule is disabled: the flag decides, not the
        // value.
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
