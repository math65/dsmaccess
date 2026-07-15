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

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func users() async throws -> [DSMUser] {
        let result = try await transport.value(
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
        let result = try await transport.value(
            api: Self.groupAPI,
            method: "list",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(-1),
                "additional": try DSMParameter.json(["description", "members"]),
            ],
            as: DSMGroupList.self
        )
        return result.groups.filter { !$0.name.isEmpty }
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
        try await transport.perform(api: Self.userAPI, method: "create", parameters: parameters)
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
