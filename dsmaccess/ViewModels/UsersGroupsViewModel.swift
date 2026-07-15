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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await session.withClient { client in
                let users = try await client.listUsers().sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                let groups = try await client.listGroups().sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                return (users, groups)
            }
            users = result.0
            groups = result.1
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = reason(for: error)
        }
    }

    func createUser(_ draft: DSMUserDraft) async -> String {
        await perform(key: "user:\(draft.name)") { client in
            try await client.createUser(draft)
            return String(localized: "Utilisateur créé : \(draft.name)")
        }
    }

    func setUser(_ user: DSMUser, disabled: Bool) async -> String {
        await perform(key: "user:\(user.name)") { client in
            try await client.setUser(user.name, disabled: disabled)
            return disabled
                ? String(localized: "Utilisateur désactivé : \(user.name)")
                : String(localized: "Utilisateur activé : \(user.name)")
        }
    }

    func deleteUser(_ user: DSMUser) async -> String {
        await perform(key: "user:\(user.name)") { client in
            try await client.deleteUser(user.name)
            return String(localized: "Utilisateur supprimé : \(user.name)")
        }
    }

    func createGroup(_ draft: DSMGroupDraft) async -> String {
        await perform(key: "group:\(draft.name)") { client in
            try await client.createGroup(draft)
            return String(localized: "Groupe créé : \(draft.name)")
        }
    }

    func deleteGroup(_ group: DSMGroup) async -> String {
        await perform(key: "group:\(group.name)") { client in
            try await client.deleteGroup(group.name)
            return String(localized: "Groupe supprimé : \(group.name)")
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(users.count) utilisateurs, \(groups.count) groupes")
    }

    private func perform(
        key: String,
        operation: (DSMClientProtocol) async throws -> String
    ) async -> String {
        busyItems.insert(key)
        defer { busyItems.remove(key) }

        do {
            let message = try await session.withClient(operation)
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
