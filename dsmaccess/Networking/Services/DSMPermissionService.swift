//
//  DSMPermissionService.swift
//  dsmaccess
//
//  Permissions granted to an account: shared folders (SYNO.Core.Share.Permission).
//

import Foundation

@MainActor
final class DSMPermissionService {
    private static let sharePermissionAPI = DSMAPI("SYNO.Core.Share.Permission")
    private static let applicationAPI = DSMAPI("SYNO.Core.AppPriv.App")
    private static let applicationRuleAPI = DSMAPI("SYNO.Core.AppPriv.Rule")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func sharePermissions(for holder: DSMPermissionHolder) async throws -> [DSMSharePermission] {
        let result = try await transport.read(
            api: Self.sharePermissionAPI,
            method: holder.listMethod,
            parameters: [
                "name": .string(holder.name),
                // Without this parameter, DSM rejects the request (403) instead of picking
                // a default.
                "user_group_type": .string(holder.apiType),
            ],
            as: DSMSharePermissionList.self
        )
        return result.shares.filter { !$0.name.isEmpty }
    }

    /// Sends only the folders passed as arguments: DSM applies the list as a patch and leaves
    /// the other folders unchanged.
    func setSharePermissions(
        _ permissions: [DSMSharePermission],
        for holder: DSMPermissionHolder
    ) async throws {
        guard !permissions.isEmpty else { return }
        try await transport.perform(
            api: Self.sharePermissionAPI,
            method: "set_by_user_group",
            parameters: [
                "name": .string(holder.name),
                "user_group_type": .string(holder.apiType),
                "permissions": try DSMParameter.json(permissions.map(SharePermissionChange.init)),
            ]
        )
    }
}

// MARK: - Seen from a shared folder

extension DSMPermissionService {
    /// The accounts of one type and their rights on a shared folder — the same grid as
    /// `sharePermissions(for:)`, read the other way round. DSM answers it through `action=enum`
    /// rather than through the `list_by_…` methods, and here `name` identifies the folder while
    /// each returned `name` is an account.
    func accountPermissions(
        onShare share: String,
        of kind: DSMPermissionHolder.Kind
    ) async throws -> [DSMSharePermission] {
        let result = try await transport.read(
            api: Self.sharePermissionAPI,
            method: "list",
            parameters: [
                "action": .string("enum"),
                "name": .string(share),
                "user_group_type": .string(kind.apiType),
                // Without it DSM leaves out the right an account holds through its groups.
                "with_inherit": .boolean(true),
                "is_unite_permission": .boolean(false),
                "offset": .integer(0),
                "limit": .integer(-1),
            ],
            as: DSMShareAccountPermissionList.self
        )
        return result.items.filter { !$0.name.isEmpty }
    }

    /// Writes the rights of the supplied accounts on one folder. As with the other direction,
    /// DSM treats the list as a patch and leaves the accounts left out untouched.
    func setAccountPermissions(
        _ permissions: [DSMSharePermission],
        onShare share: String,
        of kind: DSMPermissionHolder.Kind
    ) async throws {
        guard !permissions.isEmpty else { return }
        try await transport.perform(
            api: Self.sharePermissionAPI,
            method: "set",
            parameters: [
                "name": .string(share),
                "user_group_type": .string(kind.apiType),
                "permissions": try DSMParameter.json(permissions.map(SharePermissionChange.init)),
            ]
        )
    }
}

extension DSMPermissionService {
    /// The catalog depends on the installed packages: an application absent from the NAS has
    /// no row, and rules referring to an unknown identifier are ignored.
    func applicationPrivileges(
        for holder: DSMPermissionHolder
    ) async throws -> [DSMApplicationPrivilege] {
        let catalog = try await transport.read(
            api: Self.applicationAPI,
            method: "list",
            as: DSMApplicationList.self
        )
        let rules = try await transport.read(
            api: Self.applicationRuleAPI,
            method: "get",
            parameters: [
                "entity_type": .string(holder.entityType),
                "entity_name": .string(holder.name),
            ],
            as: DSMApplicationRuleList.self
        )
        let byApp = Dictionary(rules.rules.map { ($0.appID, $0) }, uniquingKeysWith: { first, _ in first })
        return catalog.applications.map { application in
            let rule = byApp[application.appID]
            return DSMApplicationPrivilege(
                appID: application.appID,
                name: application.name,
                isGrantedByDefault: application.isGrantedByDefault,
                decision: rule?.decision,
                restrictsAddresses: rule?.restrictsAddresses ?? false
            )
        }
    }

    /// Setting a decision and reverting to the default are two distinct methods: DSM has no
    /// "no rule" value, deleting the rule is what returns the application to its default.
    func setApplicationPrivileges(
        _ privileges: [DSMApplicationPrivilege],
        for holder: DSMPermissionHolder
    ) async throws {
        let cleared = privileges.filter { $0.decision == nil }
        if !cleared.isEmpty {
            try await transport.perform(
                api: Self.applicationRuleAPI,
                method: "delete",
                parameters: [
                    "rules": try DSMParameter.json(cleared.map { ApplicationRuleReference($0, holder: holder) }),
                ]
            )
        }
        let decided = privileges.filter { $0.decision != nil }
        guard !decided.isEmpty else { return }
        try await transport.perform(
            api: Self.applicationRuleAPI,
            method: "set",
            parameters: [
                "rules": try DSMParameter.json(decided.map { ApplicationRuleChange($0, holder: holder) }),
            ]
        )
    }
}

/// Identifies the rule to delete, with no decision: DSM expects only the application and the
/// entity.
private struct ApplicationRuleReference: Encodable {
    let appID: String
    let entityType: String
    let entityName: String

    init(_ privilege: DSMApplicationPrivilege, holder: DSMPermissionHolder) {
        appID = privilege.appID
        entityType = holder.entityType
        entityName = holder.name
    }

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case entityType = "entity_type"
        case entityName = "entity_name"
    }
}

/// DSM expresses allow and deny through two address lists, with "0.0.0.0" meaning "all".
private struct ApplicationRuleChange: Encodable {
    let appID: String
    let entityType: String
    let entityName: String
    let allowedAddresses: [String]
    let deniedAddresses: [String]

    init(_ privilege: DSMApplicationPrivilege, holder: DSMPermissionHolder) {
        appID = privilege.appID
        entityType = holder.entityType
        entityName = holder.name
        let any = [DSMApplicationRuleList.Rule.anyAddress]
        allowedAddresses = privilege.decision == .allow ? any : []
        deniedAddresses = privilege.decision == .deny ? any : []
    }

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case entityType = "entity_type"
        case entityName = "entity_name"
        case allowedAddresses = "allow_ip"
        case deniedAddresses = "deny_ip"
    }
}

/// Shape expected by `set_by_user_group`: the three levels are mutually exclusive booleans.
private struct SharePermissionChange: Encodable {
    let name: String
    let isReadOnly: Bool
    let isWritable: Bool
    let isDeny: Bool
    let isCustom: Bool

    init(_ permission: DSMSharePermission) {
        name = permission.name
        isReadOnly = permission.granted == .readOnly
        isWritable = permission.granted == .readWrite
        isDeny = permission.granted == .noAccess
        // Fine-grained permissions are set in File Station: sending them back unchanged
        // avoids erasing them when the access level is modified.
        isCustom = permission.isCustom
    }

    enum CodingKeys: String, CodingKey {
        case name
        case isReadOnly = "is_readonly"
        case isWritable = "is_writable"
        case isDeny = "is_deny"
        case isCustom = "is_custom"
    }
}
