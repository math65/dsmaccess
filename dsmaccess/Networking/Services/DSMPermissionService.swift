//
//  DSMPermissionService.swift
//  dsmaccess
//
//  Permissions accordées à un compte : dossiers partagés (SYNO.Core.Share.Permission).
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
                // Sans ce paramètre, DSM refuse la requête (403) au lieu de choisir un défaut.
                "user_group_type": .string(holder.apiType),
            ],
            as: DSMSharePermissionList.self
        )
        return result.shares.filter { !$0.name.isEmpty }
    }

    /// N'envoie que les dossiers passés en argument : DSM applique la liste comme un
    /// correctif et laisse les autres dossiers inchangés.
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

extension DSMPermissionService {
    /// Le catalogue dépend des paquets installés : une application absente du NAS n'a pas de
    /// ligne, et les règles portant sur un identifiant inconnu sont ignorées.
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

    /// Poser une décision et revenir au défaut sont deux méthodes distinctes : DSM n'a pas de
    /// valeur « aucune règle », c'est la suppression de la règle qui rend l'application au défaut.
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

/// Identifie la règle à supprimer, sans décision : DSM n'attend que l'application et l'entité.
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

/// DSM exprime autoriser et refuser par deux listes d'adresses, « 0.0.0.0 » valant « toutes ».
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

/// Forme attendue par `set_by_user_group` : les trois niveaux y sont des booléens exclusifs.
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
        // Les permissions détaillées se règlent dans File Station : les renvoyer telles
        // quelles évite de les effacer en modifiant le niveau d'accès.
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
