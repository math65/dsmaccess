//
//  DSMAccountService.swift
//  dsmaccess
//
//  Administration des utilisateurs et groupes locaux DSM.
//

import Foundation

@MainActor
final class DSMAccountService {
    private static let userAPI = DSMAPI("SYNO.Core.User")
    private static let groupAPI = DSMAPI("SYNO.Core.Group")
    private static let groupMemberAPI = DSMAPI("SYNO.Core.Group.Member")
    private static let passwordPolicyAPI = DSMAPI("SYNO.Core.User.PasswordPolicy")
    /// Réponse de DSM quand le mot de passe ne satisfait pas les règles de force du NAS.
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
        // DSM ignore « members » dans l'additional de la liste ; les membres ne s'obtiennent
        // que groupe par groupe, via SYNO.Core.Group.Member.
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

    func createUser(_ draft: DSMUserDraft) async throws {
        var parameters: [String: DSMParameter] = [
            "name": .string(draft.name),
            "password": .string(draft.password),
            "description": .string(draft.description),
            "email": .string(draft.email),
            "expired": .string("normal"),
            "cannot_chg_passwd": .boolean(false),
            "password_never_expire": .boolean(true),
        ]
        if !draft.groups.isEmpty {
            parameters["group"] = try DSMParameter.json(draft.groups)
        }
        do {
            try await transport.perform(api: Self.userAPI, method: "create", parameters: parameters)
        } catch DSMError.apiError(Self.weakPasswordCode) {
            throw DSMError.weakPassword
        }
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
