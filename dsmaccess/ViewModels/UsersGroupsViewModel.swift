//
//  UsersGroupsViewModel.swift
//  dsmaccess
//
//  État et actions du module Utilisateurs et groupes.
//

import Foundation
import Observation

@MainActor
@Observable
final class UsersGroupsViewModel {
    private(set) var users: [DSMUser] = []
    private(set) var groups: [DSMGroup] = []
    private(set) var isLoading = false
    private(set) var busyItems: Set<String> = []
    var errorMessage: String?

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        guard let client = session.client, let sid = session.sid else {
            session.clear()
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            users = try await client.listUsers(sid: sid).sorted(using: KeyPathComparator(\.name))
            groups = try await client.listGroups(sid: sid).sorted(using: KeyPathComparator(\.name))
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = reason(for: error)
        }
    }

    func createUser(_ draft: DSMUserDraft) async -> String {
        await perform(key: "user:\(draft.name)") { client, sid in
            try await client.createUser(draft, sid: sid)
            return String(localized: "Utilisateur créé : \(draft.name)")
        }
    }

    func setUser(_ user: DSMUser, disabled: Bool) async -> String {
        await perform(key: "user:\(user.name)") { client, sid in
            try await client.setUser(user.name, disabled: disabled, sid: sid)
            return disabled
                ? String(localized: "Utilisateur désactivé : \(user.name)")
                : String(localized: "Utilisateur activé : \(user.name)")
        }
    }

    func deleteUser(_ user: DSMUser) async -> String {
        await perform(key: "user:\(user.name)") { client, sid in
            try await client.deleteUser(user.name, sid: sid)
            return String(localized: "Utilisateur supprimé : \(user.name)")
        }
    }

    func createGroup(_ draft: DSMGroupDraft) async -> String {
        await perform(key: "group:\(draft.name)") { client, sid in
            try await client.createGroup(draft, sid: sid)
            return String(localized: "Groupe créé : \(draft.name)")
        }
    }

    func deleteGroup(_ group: DSMGroup) async -> String {
        await perform(key: "group:\(group.name)") { client, sid in
            try await client.deleteGroup(group.name, sid: sid)
            return String(localized: "Groupe supprimé : \(group.name)")
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(users.count) utilisateurs, \(groups.count) groupes")
    }

    private func perform(
        key: String,
        operation: (DSMClientProtocol, String) async throws -> String
    ) async -> String {
        guard let client = session.client, let sid = session.sid else {
            return String(localized: "Session expirée.")
        }
        busyItems.insert(key)
        defer { busyItems.remove(key) }

        do {
            let message = try await operation(client, sid)
            await load()
            return message
        } catch {
            return String(localized: "Échec de l’opération : \(reason(for: error))")
        }
    }

    private func reason(for error: Error) -> String {
        if case let DSMError.apiError(code) = error {
            switch code {
            case 400: return String(localized: "le nom est invalide ou existe déjà")
            case 402: return String(localized: "permission refusée")
            case 407: return String(localized: "le mot de passe ne respecte pas la stratégie du NAS")
            default: break
            }
        }
        return (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}
