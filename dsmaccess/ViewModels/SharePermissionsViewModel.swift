//
//  SharePermissionsViewModel.swift
//  dsmaccess
//
//  État de l'écran des permissions de dossiers partagés d'un compte.
//

import Foundation
import Observation

@MainActor
@Observable
final class SharePermissionsViewModel {
    let userName: String
    private(set) var permissions: [DSMSharePermission] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?

    private let session: SessionStore
    /// État tel que le NAS l'a renvoyé, pour n'envoyer que les lignes réellement changées.
    private var loaded: [String: DSMSharePermissionLevel?] = [:]

    init(userName: String, session: SessionStore) {
        self.userName = userName
        self.session = session
    }

    var hasChanges: Bool { !changedPermissions.isEmpty }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(permissions.count) dossiers partagés")
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let shares = try await session.withClient { client in
                try await client.sharePermissions(forUser: userName).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
            permissions = shares
            loaded = Dictionary(uniqueKeysWithValues: shares.map { ($0.name, $0.granted) })
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setLevel(_ level: DSMSharePermissionLevel?, for share: DSMSharePermission) {
        guard let index = permissions.firstIndex(where: { $0.id == share.id }) else { return }
        permissions[index].granted = level
    }

    func save() async -> DSMOperationOutcome {
        let changes = changedPermissions
        guard !changes.isEmpty else {
            return .success(String(localized: "Aucune modification à enregistrer."))
        }
        isSaving = true
        defer { isSaving = false }

        do {
            try await session.withClient { client in
                try await client.setSharePermissions(changes, forUser: userName)
            }
            loaded = Dictionary(uniqueKeysWithValues: permissions.map { ($0.name, $0.granted) })
            return .success(
                String(localized: "Permissions enregistrées : \(changes.count) dossiers modifiés.")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec de l’enregistrement : \(reason)"))
        }
    }

    private var changedPermissions: [DSMSharePermission] {
        permissions.filter { permission in
            guard let original = loaded[permission.name] else { return false }
            return original != permission.granted
        }
    }
}
