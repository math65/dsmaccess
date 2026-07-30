//
//  SharePermissionsViewModel.swift
//  dsmaccess
//
//  State of the permissions screen for an account or a group: shared folders and
//  applications, saved together.
//

import Foundation
import Observation

@MainActor
@Observable
final class SharePermissionsViewModel {
    let holder: DSMPermissionHolder
    private(set) var permissions: [DSMSharePermission] = []
    private(set) var applications: [DSMApplicationPrivilege] = []
    /// The NAS groups and the account's membership. Empty for a group: a group belongs to
    /// nothing, and DSM does not offer it this tab either.
    private(set) var groups: [DSMGroup] = []
    private(set) var memberships: Set<String> = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// The NAS can expose folders without exposing applications: the pane then says why it
    /// is empty instead of implying no application exists.
    private(set) var applicationsUnavailable: String?
    var errorMessage: String?

    private let session: SessionStore
    /// State as the NAS returned it, so only the rows that actually changed get sent.
    private var loadedShares: [String: DSMSharePermissionLevel?] = [:]
    private var loadedApplications: [String: DSMApplicationDecision?] = [:]
    private var loadedMemberships: Set<String> = []

    init(holder: DSMPermissionHolder, session: SessionStore) {
        self.holder = holder
        self.session = session
    }

    var hasChanges: Bool {
        !changedShares.isEmpty || !changedApplications.isEmpty || memberships != loadedMemberships
    }

    var editsMemberships: Bool {
        if case .user = holder { return true }
        return false
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "common.count.shared_folders", defaultValue: "\(permissions.count) shared folders")
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

        if editsMemberships {
            do {
                let all = try await session.withClient { client in
                    try await client.listGroups().sorted {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                }
                // "users" is left out: the NAS assigns it to every account and refuses to change
                // it, so listing it would offer a switch that cannot move.
                groups = all.filter { !$0.isEveryone }
                memberships = Set(groups.filter { $0.members.contains(holder.name) }.map(\.name))
                loadedMemberships = memberships
            } catch {
                guard !DSMError.isCancellation(error) else { return }
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
                return
            }
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

    func setMembership(_ isMember: Bool, of group: DSMGroup) {
        if isMember { memberships.insert(group.name) } else { memberships.remove(group.name) }
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
        let joining = memberships.subtracting(loadedMemberships).sorted()
        let leaving = loadedMemberships.subtracting(memberships).sorted()
        guard !shares.isEmpty || !privileges.isEmpty || !joining.isEmpty || !leaving.isEmpty else {
            return .success(String(localized: "share_permissions.save.no_changes"))
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
                if !joining.isEmpty || !leaving.isEmpty {
                    try await client.setMemberships(
                        of: holder.name,
                        joining: joining,
                        leaving: leaving
                    )
                }
            }
            loadedShares = Dictionary(uniqueKeysWithValues: permissions.map { ($0.name, $0.granted) })
            loadedApplications = Dictionary(uniqueKeysWithValues: applications.map { ($0.appID, $0.decision) })
            loadedMemberships = memberships
            return .success(
                savedSummary(
                    shares: shares.count,
                    applications: privileges.count,
                    groups: joining.count + leaving.count
                )
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.save_failed", defaultValue: "Saving failed: \(reason)"))
        }
    }

    private func savedSummary(shares: Int, applications: Int, groups: Int) -> String {
        if groups > 0, shares == 0, applications == 0 {
            return String(localized: "share_permissions.save.success.groups", defaultValue: "Permissions saved: \(groups) groups changed.")
        }
        if groups > 0 {
            return String(
                localized: "share_permissions.save.success.folders_applications_groups",
                defaultValue: "Permissions saved: \(shares) shared folders, \(applications) applications and \(groups) groups changed."
            )
        }
        if shares > 0, applications > 0 {
            return String(
                localized: "share_permissions.save.success.folders_applications",
                defaultValue: "Permissions saved: \(shares) shared folders and \(applications) applications changed."
            )
        }
        if applications > 0 {
            return String(localized: "share_permissions.save.success.applications", defaultValue: "Permissions saved: \(applications) applications changed.")
        }
        return String(localized: "share_permissions.save.success.folders", defaultValue: "Permissions saved: \(shares) shared folders changed.")
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
