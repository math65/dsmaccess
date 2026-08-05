//
//  ShareAccountPermissionsViewModel.swift
//  dsmaccess
//
//  The accounts reaching one shared folder — DSM's grid read from the folder rather than
//  from the account.
//

import Foundation
import Observation

@MainActor
@Observable
final class ShareAccountPermissionsViewModel {
    let shareName: String
    var kind: DSMPermissionHolder.Kind {
        didSet {
            guard kind != oldValue else { return }
            Task { await load() }
        }
    }
    private(set) var permissions: [DSMSharePermission] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?

    private let session: SessionStore
    /// State as the NAS returned it, so only the rows that actually changed get sent.
    private var loaded: [DSMPermissionHolder.Kind: [String: DSMSharePermissionLevel?]] = [:]
    private var loadGeneration = 0

    init(shareName: String, session: SessionStore) {
        self.shareName = shareName
        self.session = session
        self.kind = .user
    }

    var hasChanges: Bool { !changedPermissions.isEmpty }

    var summary: String {
        if let errorMessage { return errorMessage }
        switch kind {
        case .user:
            return String(localized: "share_permissions.accounts.count.users", defaultValue: "\(permissions.count) users")
        case .group:
            return String(localized: "share_permissions.accounts.count.groups", defaultValue: "\(permissions.count) groups")
        }
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requested = kind
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let accounts = try await session.withClient { client in
                try await client.shareAccountPermissions(onShare: shareName, of: requested).sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }
            guard generation == loadGeneration else { return }
            permissions = accounts
            loaded[requested] = Dictionary(uniqueKeysWithValues: accounts.map { ($0.name, $0.granted) })
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            permissions = []
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setLevel(_ level: DSMSharePermissionLevel?, for account: DSMSharePermission) {
        guard let index = permissions.firstIndex(where: { $0.id == account.id }) else { return }
        permissions[index].granted = level
    }

    func save() async -> DSMOperationOutcome {
        let changed = changedPermissions
        guard !changed.isEmpty else {
            return .success(String(localized: "share_permissions.save.no_changes"))
        }
        let written = kind
        isSaving = true
        defer { isSaving = false }

        do {
            try await session.withClient { client in
                try await client.setShareAccountPermissions(
                    changed,
                    onShare: shareName,
                    of: written
                )
            }
            loaded[written] = Dictionary(uniqueKeysWithValues: permissions.map { ($0.name, $0.granted) })
            return .success(
                String(
                    localized: "share_permissions.accounts.save.success",
                    defaultValue: "Permissions saved: \(changed.count) accounts changed on \(shareName)."
                )
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.save_failed", defaultValue: "Saving failed: \(reason)"))
        }
    }

    private var changedPermissions: [DSMSharePermission] {
        guard let original = loaded[kind] else { return [] }
        return permissions.filter { permission in
            guard let before = original[permission.name] else { return false }
            return before != permission.granted
        }
    }
}
