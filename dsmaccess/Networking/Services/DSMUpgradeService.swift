//
//  DSMUpgradeService.swift
//  dsmaccess
//
//  Mise à jour manuelle de DSM : envoi du .pat, vérification, lancement et suivi.
//

import Foundation

@MainActor
final class DSMUpgradeService {
    private static let patchAPI = DSMAPI("SYNO.Core.Upgrade.Patch")
    private static let preCheckAPI = DSMAPI("SYNO.Core.Upgrade.PreCheck")
    private static let upgradeAPI = DSMAPI("SYNO.Core.Upgrade")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    /// Envoie le fichier de mise à jour. Contrat relevé sur DSM 7.4 : api, method, version et
    /// session vont dans la query, le corps multipart ne porte que « target » et le fichier —
    /// même convention que l'envoi d'un paquet et que File Station.
    func uploadPatch(
        at fileURL: URL,
        progress: @escaping DSMTransferProgressHandler = { _ in }
    ) async throws {
        guard fileURL.isFileURL else {
            throw DSMError.network(String(localized: "Ce fichier n’est pas accessible."))
        }
        guard fileURL.pathExtension.caseInsensitiveCompare("pat") == .orderedSame else {
            throw DSMError.network(String(localized: "Le fichier de mise à jour doit avoir l’extension .pat."))
        }
        guard let taille = try? await MultipartBodyFile.fileSize(at: fileURL), taille > 0 else {
            throw DSMError.network(String(localized: "Ce fichier de mise à jour est vide ou illisible."))
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let route = try await transport.multipartRoute(api: Self.patchAPI, method: "upload")
        let resolved = try await transport.resolvedAPI(Self.patchAPI)
        let uploadURL = try transport.makeURL(path: resolved.path, parameters: route.fields)
        let bodyURL = try await MultipartBodyFile.create(
            fields: ["target": "active"],
            fileURL: fileURL,
            fileFieldName: "file",
            boundary: boundary
        )
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        // Un .pat pèse plusieurs centaines de mégaoctets : le délai par défaut ne suffit pas.
        request.timeoutInterval = 900
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        let (data, response) = try await transport.upload(
            for: request,
            fromFile: bodyURL,
            progress: progress
        )
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DSMError.invalidResponse
        }
        let result = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
        guard result.success else {
            throw transport.error(from: result.error)
        }
    }

    /// Ce que DSM dit du fichier reçu, dont les paquets qu'il cessera de prendre en charge.
    func preCheck() async throws -> DSMUpgradePreCheck {
        try await transport.read(api: Self.preCheckAPI, method: "get", as: DSMUpgradePreCheck.self)
    }

    /// Lance l'installation. Mutation en tentative unique : un délai dépassé ne doit jamais
    /// relancer une mise à jour système.
    func start() async throws {
        try await transport.perform(api: Self.upgradeAPI, method: "start")
    }

    func progress() async throws -> DSMUpgradeProgress {
        try await transport.read(api: Self.upgradeAPI, method: "progress", as: DSMUpgradeProgress.self)
    }

    /// Interroge l'hôte sans passer par la session : pendant le redémarrage il n'y en a plus.
    /// `boot_done` dit que le NAS répond, pas que la mise à jour est finie — seule une
    /// reconnexion réussie le prouve.
    func isBackOnline() async -> Bool {
        // makeURL préfixe /webapi/ : pingpong vit ailleurs, l'URL se construit à la main.
        var components = URLComponents()
        components.scheme = transport.endpoint.scheme
        components.host = transport.endpoint.host
        components.port = transport.endpoint.port
        components.path = "/webman/pingpong.cgi"
        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        guard let (data, response) = try? await transport.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let state = try? JSONDecoder().decode(DSMBootState.self, from: data)
        else {
            return false
        }
        return state.isBootDone
    }
}
