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

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func sharePermissions(for holder: DSMShareHolder) async throws -> [DSMSharePermission] {
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
        for holder: DSMShareHolder
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
