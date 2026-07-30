//
//  DSMUpgradeService.swift
//  dsmaccess
//
//  Manual DSM update: uploading the .pat, checking, starting and tracking it.
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

    /// Uploads the update file. Contract captured on DSM 7.4: api, method, version and session
    /// go in the query, the multipart body carries only "target" and the file — same
    /// convention as uploading a package and as File Station.
    func uploadPatch(
        at fileURL: URL,
        progress: @escaping DSMTransferProgressHandler = { _ in }
    ) async throws {
        guard fileURL.isFileURL else {
            throw DSMError.network(String(localized: "dsm_update.file.unreadable.error"))
        }
        guard fileURL.pathExtension.caseInsensitiveCompare("pat") == .orderedSame else {
            throw DSMError.network(String(localized: "dsm_update.file.extension.error"))
        }
        guard let taille = try? await MultipartBodyFile.fileSize(at: fileURL), taille > 0 else {
            throw DSMError.network(String(localized: "dsm_update.file.empty.error"))
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
        // A .pat weighs several hundred megabytes: the default timeout is not enough.
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

    /// What DSM says about the file it received, including the packages it will stop supporting.
    func preCheck() async throws -> DSMUpgradePreCheck {
        try await transport.read(api: Self.preCheckAPI, method: "get", as: DSMUpgradePreCheck.self)
    }

    /// Starts the installation. Single-attempt mutation: a timeout must never restart a system
    /// update.
    func start() async throws {
        try await transport.perform(api: Self.upgradeAPI, method: "start")
    }

    func progress() async throws -> DSMUpgradeProgress {
        try await transport.read(api: Self.upgradeAPI, method: "progress", as: DSMUpgradeProgress.self)
    }

    /// Queries the host without going through the session: during the restart there is no
    /// session left. `boot_done` says the NAS is answering, not that the update is finished —
    /// only a successful reconnection proves that.
    func isBackOnline() async -> Bool {
        // makeURL prefixes /webapi/: pingpong lives elsewhere, so the URL is built by hand.
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
