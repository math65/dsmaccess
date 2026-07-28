//
//  SharePermissionsViewModel.swift
//  dsmaccess
//
//  État de l'écran des permissions d'un compte ou d'un groupe : dossiers partagés et
//  applications, enregistrés ensemble.
//

import Foundation
import Observation

@MainActor
@Observable
final class SharePermissionsViewModel {
    let holder: DSMPermissionHolder
    private(set) var permissions: [DSMSharePermission] = []
    private(set) var applications: [DSMApplicationPrivilege] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// Le NAS peut exposer les dossiers sans exposer les applications : le volet dit alors
    /// pourquoi il est vide au lieu de laisser croire qu'aucune application n'existe.
    private(set) var applicationsUnavailable: String?
    var errorMessage: String?

    private let session: SessionStore
    /// État tel que le NAS l'a renvoyé, pour n'envoyer que les lignes réellement changées.
    private var loadedShares: [String: DSMSharePermissionLevel?] = [:]
    private var loadedApplications: [String: DSMApplicationDecision?] = [:]

    init(holder: DSMPermissionHolder, session: SessionStore) {
        self.holder = holder
        self.session = session
    }

    var hasChanges: Bool { !changedShares.isEmpty || !changedApplications.isEmpty }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(permissions.count) dossiers partagés")
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        applicationsUnavailable = nil
        defer { isLoading = false }

        do {
            let shares = try await session.withClient { client in
                try await client.sharePermissions(for: holder).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
            permissions = shares
            loadedShares = Dictionary(uniqueKeysWithValues: shares.map { ($0.name, $0.granted) })
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return
        }

        do {
            let privileges = try await session.withClient { client in
                try await client.applicationPrivileges(for: holder).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
            applications = privileges
            loadedApplications = Dictionary(uniqueKeysWithValues: privileges.map { ($0.appID, $0.decision) })
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            applications = []
            loadedApplications = [:]
            applicationsUnavailable = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setLevel(_ level: DSMSharePermissionLevel?, for share: DSMSharePermission) {
        guard let index = permissions.firstIndex(where: { $0.id == share.id }) else { return }
        permissions[index].granted = level
    }

    func setDecision(
        _ decision: DSMApplicationDecision?,
        for application: DSMApplicationPrivilege
    ) {
        guard let index = applications.firstIndex(where: { $0.id == application.id }) else { return }
        applications[index].decision = decision
    }

    func save() async -> DSMOperationOutcome {
        let shares = changedShares
        let privileges = changedApplications
        guard !shares.isEmpty || !privileges.isEmpty else {
            return .success(String(localized: "Aucune modification à enregistrer."))
        }
        isSaving = true
        defer { isSaving = false }

        do {
            try await session.withClient { client in
                if !shares.isEmpty {
                    try await client.setSharePermissions(shares, for: holder)
                }
                if !privileges.isEmpty {
                    try await client.setApplicationPrivileges(privileges, for: holder)
                }
            }
            loadedShares = Dictionary(uniqueKeysWithValues: permissions.map { ($0.name, $0.granted) })
            loadedApplications = Dictionary(uniqueKeysWithValues: applications.map { ($0.appID, $0.decision) })
            return .success(savedSummary(shares: shares.count, applications: privileges.count))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec de l’enregistrement : \(reason)"))
        }
    }

    private func savedSummary(shares: Int, applications: Int) -> String {
        if shares > 0, applications > 0 {
            return String(
                localized: "Permissions enregistrées : \(shares) dossiers et \(applications) applications modifiés."
            )
        }
        if applications > 0 {
            return String(localized: "Permissions enregistrées : \(applications) applications modifiées.")
        }
        return String(localized: "Permissions enregistrées : \(shares) dossiers modifiés.")
    }

    private var changedShares: [DSMSharePermission] {
        permissions.filter { permission in
            guard let original = loadedShares[permission.name] else { return false }
            return original != permission.granted
        }
    }

    private var changedApplications: [DSMApplicationPrivilege] {
        applications.filter { application in
            guard let original = loadedApplications[application.appID] else { return false }
            return original != application.decision
        }
    }
}
