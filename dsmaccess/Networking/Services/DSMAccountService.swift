//
//  DSMAccountService.swift
//  dsmaccess
//
//  Administration of DSM local users and groups.
//

import Foundation

@MainActor
final class DSMAccountService {
    private static let userAPI = DSMAPI("SYNO.Core.User")
    private static let groupAPI = DSMAPI("SYNO.Core.Group")
    private static let groupMemberAPI = DSMAPI("SYNO.Core.Group.Member")
    private static let passwordPolicyAPI = DSMAPI("SYNO.Core.User.PasswordPolicy")
    /// DSM's answer when the password does not satisfy the NAS's strength rules.
    private static let weakPasswordCode = 3121

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func users() async throws -> [DSMUser] {
        let result = try await transport.read(
            api: Self.userAPI,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(-1),
                "additional": try DSMParameter.json(["description", "email", "expired", "groups"]),
            ],
            as: DSMUserList.self
        )
        return result.users.filter { !$0.name.isEmpty }
    }

    func groups() async throws -> [DSMGroup] {
        let result = try await transport.read(
            api: Self.groupAPI,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(-1),
                "additional": try DSMParameter.json(["description"]),
            ],
            as: DSMGroupList.self
        )
        var groups = result.groups.filter { !$0.name.isEmpty }
        // DSM ignores "members" in the list's additional; members can only be obtained group
        // by group, through SYNO.Core.Group.Member.
        for index in groups.indices {
            let members = try await transport.read(
                api: Self.groupMemberAPI,
                method: "list",
                parameters: ["group": .string(groups[index].name)],
                as: DSMGroupMemberList.self
            )
            groups[index].members = members.names
        }
        return groups
    }

    /// DSM 7.4 accepts the "group" parameter of SYNO.Core.User.create and answers `success`,
    /// but does not add the account to any of those groups: membership can only be obtained in
    /// a second call, through SYNO.Core.Group.Member. The account exists as of the first step,
    /// hence the dedicated error if the second one fails.
    func createUser(_ draft: DSMUserDraft) async throws {
        let parameters: [String: DSMParameter] = [
            "name": .string(draft.name),
            "password": .string(draft.password),
            "description": .string(draft.description),
            "email": .string(draft.email),
            "expired": .string("normal"),
            "cannot_chg_passwd": .boolean(false),
            "password_never_expire": .boolean(true),
        ]
        do {
            try await transport.perform(api: Self.userAPI, method: "create", parameters: parameters)
        } catch DSMError.apiError(Self.weakPasswordCode) {
            throw DSMError.weakPassword
        }

        let refused = try await joinAll(draft.name, to: draft.groups)
        guard refused.isEmpty else {
            throw DSMError.userCreatedWithoutGroups(name: draft.name, groups: refused)
        }
    }

    /// Adds an account to each group, and returns those DSM refused. Every group is attempted:
    /// stopping at the first refusal used to drop the remaining ones silently, so a single
    /// unwritable group cost the memberships listed after it.
    private func joinAll(_ user: String, to groups: [String]) async throws -> [String] {
        var refused: [String] = []
        for group in groups where group != DSMGroup.everyoneName {
            do {
                try await changeMembership(of: user, in: group, joins: true)
            } catch {
                guard !DSMError.isCancellation(error) else { throw error }
                refused.append(group)
            }
        }
        return refused
    }

    /// Applies an account's membership to a set of groups. DSM can only modify one group at a
    /// time: it is the group that carries its members, not the other way around. Every group is
    /// attempted before reporting, so one refusal does not discard the changes that follow it.
    func setMemberships(of user: String, joining: [String], leaving: [String]) async throws {
        var refused = try await joinAll(user, to: joining)
        for group in leaving where group != DSMGroup.everyoneName {
            do {
                try await changeMembership(of: user, in: group, joins: false)
            } catch {
                guard !DSMError.isCancellation(error) else { throw error }
                refused.append(group)
            }
        }
        guard refused.isEmpty else { throw DSMError.membershipsRefused(groups: refused) }
    }

    private func changeMembership(of user: String, in group: String, joins: Bool) async throws {
        try await transport.perform(
            api: Self.groupMemberAPI,
            method: "change",
            parameters: [
                "group": .string(group),
                // The parameter is singular, and "add" answers success without doing anything.
                joins ? "add_member" : "remove_member": try DSMParameter.json([user]),
            ]
        )
    }

    func passwordPolicy() async throws -> DSMPasswordPolicy {
        try await transport.read(
            api: Self.passwordPolicyAPI,
            method: "get",
            as: DSMPasswordPolicy.self
        )
    }

    func setUser(_ name: String, disabled: Bool) async throws {
        try await transport.perform(
            api: Self.userAPI,
            method: "set",
            parameters: [
                "name": .string(name),
                "expired": .string(disabled ? "now" : "normal"),
            ]
        )
    }

    func deleteUser(_ name: String) async throws {
        try await transport.perform(
            api: Self.userAPI,
            method: "delete",
            parameters: ["name": try DSMParameter.json([name])]
        )
    }

    func createGroup(_ draft: DSMGroupDraft) async throws {
        try await transport.perform(
            api: Self.groupAPI,
            method: "create",
            parameters: [
                "name": .string(draft.name),
                "description": .string(draft.description),
            ]
        )
    }

    func deleteGroup(_ name: String) async throws {
        try await transport.perform(
            api: Self.groupAPI,
            method: "delete",
            parameters: ["name": try DSMParameter.json([name])]
        )
    }
}
