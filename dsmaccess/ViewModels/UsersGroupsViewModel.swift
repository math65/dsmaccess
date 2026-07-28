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
    /// Règles de mot de passe du NAS, énoncées dans le formulaire de création. Nil tant
    /// qu'elles n'ont pas été lues, ou si ce NAS ne les expose pas.
    private(set) var passwordPolicy: DSMPasswordPolicy?
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }

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
            guard generation == loadGeneration else { return }
            users = result.0
            groups = result.1
            // Aide à la saisie : un NAS qui n'expose pas ses règles ne doit pas empêcher
            // d'administrer les comptes, le formulaire s'affichera simplement sans elles.
            passwordPolicy = try? await session.withClient { try await $0.passwordPolicy() }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = reason(for: error)
        }
    }

    func createUser(_ draft: DSMUserDraft) async -> DSMOperationOutcome {
        await perform(key: "user:\(draft.name)") { client in
            do {
                try await client.createUser(draft)
                return String(localized: "Utilisateur créé : \(draft.name)")
            } catch DSMError.userCreatedWithoutGroups {
                // Le compte existe : resoumettre le formulaire ne ferait qu'échouer sur un
                // nom déjà pris. L'opération se termine donc, en énonçant ce qui reste à faire.
                return String(
                    localized: "Utilisateur créé : \(draft.name). Son ajout aux groupes a échoué, attribuez-les depuis la liste des groupes."
                )
            }
        }
    }

    func setUser(_ user: DSMUser, disabled: Bool) async -> DSMOperationOutcome {
        await perform(key: "user:\(user.name)") { client in
            try await client.setUser(user.name, disabled: disabled)
            return disabled
                ? String(localized: "Utilisateur désactivé : \(user.name)")
                : String(localized: "Utilisateur activé : \(user.name)")
        }
    }

    func deleteUser(_ user: DSMUser) async -> DSMOperationOutcome {
        await perform(key: "user:\(user.name)") { client in
            try await client.deleteUser(user.name)
            return String(localized: "Utilisateur supprimé : \(user.name)")
        }
    }

    func createGroup(_ draft: DSMGroupDraft) async -> DSMOperationOutcome {
        await perform(key: "group:\(draft.name)") { client in
            try await client.createGroup(draft)
            return String(localized: "Groupe créé : \(draft.name)")
        }
    }

    func deleteGroup(_ group: DSMGroup) async -> DSMOperationOutcome {
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
    ) async -> DSMOperationOutcome {
        busyItems.insert(key)
        defer { busyItems.remove(key) }

        do {
            let message = try await session.withClient(operation)
            await load()
            return .success(message)
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "Échec de l’opération : \(reason(for: error))"))
        }
    }

    private func reason(for error: Error) -> String {
        // Les messages sont des fragments : ils complètent « Échec de l'opération : ».
        if case DSMError.weakPassword = error {
            return String(localized: "le mot de passe ne respecte pas les règles du NAS")
        }
        if case let DSMError.apiError(code) = error {
            switch code {
            case 400: return String(localized: "le nom est invalide ou existe déjà")
            case 402: return String(localized: "permission refusée")
            // DSM 7.4 signale un mot de passe trop faible par 3121, traduit en amont ;
            // 407 reste pour les versions qui utilisent ce code.
            case 407: return String(localized: "le mot de passe ne respecte pas les règles du NAS")
            default: break
            }
        }
        return (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}
