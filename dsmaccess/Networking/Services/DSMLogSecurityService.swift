//
//  DSMLogSecurityService.swift
//  dsmaccess
//
//  Journal système du NAS et liste de blocage du blocage automatique.
//

import Foundation

@MainActor
final class DSMLogSecurityService {
    private static let logAPI = DSMAPI("SYNO.Core.SyslogClient.Log")
    private static let blockListAPI = DSMAPI("SYNO.Core.Security.AutoBlock.Rules")
    private static let transferLoggingAPI = DSMAPI("SYNO.Core.SyslogClient.FileTransfer")
    private static let loginActivityAPI = DSMAPI("SYNO.SecurityAdvisor.LoginActivity")
    /// ⚠️ Cette API porte les **réglages** du blocage automatique et n'a pas de méthode `list` :
    /// la liste des adresses vit dans `AutoBlock.Rules`.
    private static let autoBlockAPI = DSMAPI("SYNO.Core.Security.AutoBlock")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    /// Page du journal système. `keyword` est filtré par le NAS lui-même ; le niveau, lui, ne
    /// l'est pas : vérifié sur DSM 7.4, le paramètre `level` est accepté puis ignoré, et le
    /// filtrage par gravité se fait donc côté app.
    ///
    /// ⚠️ `logtype` est indispensable : sans lui le NAS ne renvoie que le journal système, alors
    /// qu'il en tient un par protocole en plus de celui des connexions. Un type que le NAS ne
    /// connaît pas renvoie zéro entrée **sans erreur** — d'où l'intérêt de ne proposer que les
    /// journaux réellement actifs.
    func systemLogs(
        kind: SystemLogKind,
        limit: Int,
        offset: Int = 0,
        keyword: String? = nil
    ) async throws -> SystemLogPage {
        var parameters: [String: DSMParameter] = [
            "logtype": .string(kind.rawValue),
            "offset": .integer(offset),
            "limit": .integer(limit),
            "sort_by": "time",
            "sort_direction": "DESC",
        ]
        if let keyword, !keyword.isEmpty {
            parameters["keyword"] = .string(keyword)
        }
        return try await transport.read(
            api: Self.logAPI,
            method: "list",
            parameters: parameters,
            as: SystemLogPage.self
        )
    }

    /// Écrit le journal demandé dans un fichier produit par le NAS. L'export porte sur le
    /// journal entier, non sur les tranches chargées : 1,9 Mo pour le journal système du NAS de
    /// développement, sans avoir eu à le parcourir.
    ///
    /// En cas de refus, DSM renvoie du JSON à la place du fichier : c'est le type de contenu
    /// qui le trahit, comme pour les téléchargements de File Station.
    ///
    /// ⚠️ Le format se demande dans **`format`**, et non dans `type` comme le fait
    /// `SYNO.ResourceMonitor.Log`. Vérifié sur DSM 7.4 : avec `type`, le paramètre est ignoré
    /// sans erreur et le NAS renvoie du HTML — un fichier nommé `.csv` contenant du HTML.
    func exportSystemLog(
        kind: SystemLogKind,
        format: SystemLogExportFormat,
        to destination: URL
    ) async throws {
        let url = try await transport.makeURL(
            api: Self.logAPI,
            method: "export",
            parameters: [
                "logtype": .string(kind.rawValue),
                "format": .string(format.rawValue),
            ]
        )
        let (temporaryURL, response) = try await transport.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        if let mimeType = response.mimeType, mimeType.contains("json") {
            let data = try await MultipartBodyFile.readData(at: temporaryURL)
            let decoded = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
            guard !decoded.success else { throw DSMError.invalidResponse }
            throw transport.error(from: decoded.error)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
    }

    /// Protocoles dont les transferts sont journalisés. Détermine les journaux à proposer.
    func fileTransferLogging() async throws -> FileTransferLogging {
        try await transport.read(
            api: Self.transferLoggingAPI,
            method: "get",
            as: FileTransferLogging.self
        )
    }

    /// Adresses que le blocage automatique refuse.
    ///
    /// ⚠️ `SYNO.Core.Security.AutoBlock` n'a **pas** de méthode `list` : elle ne sert qu'aux
    /// réglages du blocage. L'appeler valait un code 103, signalé par un utilisateur avant
    /// d'être reproduit sur le NAS de développement. La liste vit dans `AutoBlock.Rules`, qui
    /// exige `action` et `type` — sans eux, le NAS répond 5100.
    func blockedAddresses(limit: Int) async throws -> BlockedAddressPage {
        try await transport.read(
            api: Self.blockListAPI,
            method: "list",
            parameters: [
                "action": .string("load"),
                "offset": .integer(0),
                "limit": .integer(limit),
                "type": .string(Self.denyList),
            ],
            as: BlockedAddressPage.self
        )
    }

    /// Choisit les protocoles dont les transferts sont journalisés. Activer un protocole fait
    /// apparaître son journal ; le couper ne supprime pas les entrées déjà consignées.
    ///
    /// Les six champs partent ensemble : vérifié sur DSM 7.4, `set` ignore les champs absents
    /// — un appel sans aucun paramètre réussit sans rien changer — mais tout envoyer évite de
    /// dépendre de ce comportement.
    ///
    /// Mutation : chemin sans nouvelle tentative.
    func setFileTransferLogging(_ logging: FileTransferLogging) async throws {
        let parameters = logging.parameters.mapValues { DSMParameter.boolean($0) }
        try await transport.perform(
            api: Self.transferLoggingAPI,
            method: "set",
            parameters: parameters
        )
    }

    /// Réglages du blocage automatique.
    func autoBlockSettings() async throws -> AutoBlockSettings {
        try await transport.read(
            api: Self.autoBlockAPI,
            method: "get",
            as: AutoBlockSettings.self
        )
    }

    /// Mutation : chemin sans nouvelle tentative.
    func setAutoBlockSettings(_ settings: AutoBlockSettings) async throws {
        try await transport.perform(
            api: Self.autoBlockAPI,
            method: "set",
            parameters: [
                "enable": .boolean(settings.isEnabled),
                "attempts": .integer(settings.attempts),
                "within_mins": .integer(settings.withinMinutes),
                "expire_day": .integer(settings.expiryDays),
            ]
        )
    }

    /// Activité de connexion relevée par le Conseiller de sécurité : connexions inhabituelles
    /// et tentatives répétées. Lecture seule.
    func loginActivity(limit: Int) async throws -> LoginActivityPage {
        try await transport.read(
            api: Self.loginActivityAPI,
            method: "list",
            parameters: ["offset": .integer(0), "limit": .integer(limit)],
            as: LoginActivityPage.self
        )
    }

    /// Retire des adresses de la liste de blocage. Mutation : chemin sans nouvelle tentative.
    func unblockAddresses(_ addresses: [String]) async throws {
        try await transport.perform(
            api: Self.blockListAPI,
            method: "delete",
            parameters: [
                "type": .string(Self.denyList),
                "ip": try .json(addresses),
            ]
        )
    }

    /// La même API sert la liste d'autorisation ; seule celle de blocage est exposée par l'app.
    private static let denyList = "deny"
}
