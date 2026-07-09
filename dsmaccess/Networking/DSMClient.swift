//
//  DSMClient.swift
//  dsmaccess
//
//  Client de la WebAPI Synology : découverte des chemins d'API, login (avec 2FA),
//  infos système, logout. Tout en async/await, isolé sur le MainActor.
//

import Foundation

/// Contrat du client DSM — permet de mocker le réseau dans les tests et facilite
/// l'ajout futur d'API (File Station, utilisateurs, Docker…) sans toucher à l'auth.
protocol DSMClientProtocol: AnyObject {
    func apiInfo(for apis: [String]) async throws -> [String: APIInfoEntry]
    func login(account: String, password: String,
               otpCode: String?, deviceID: String?,
               rememberDevice: Bool) async throws -> LoginResult
    func systemInfo(sid: String) async throws -> SystemInfo
    /// Dossiers partagés racine (File Station).
    func listShares(sid: String) async throws -> [FileStationItem]
    /// Contenu d'un dossier (File Station), `folderPath` étant un chemin absolu NAS.
    func list(folderPath: String, sid: String) async throws -> [FileStationItem]
    /// Télécharge un fichier (ou un dossier, renvoyé en ZIP par DSM) vers `destination`.
    func downloadFile(path: String, sid: String, to destination: URL) async throws
    /// Crée un dossier `name` dans `folderPath`.
    func createFolder(in folderPath: String, name: String, sid: String) async throws
    /// Renomme l'élément situé à `path` en `name`.
    func rename(path: String, to name: String, sid: String) async throws
    /// Supprime l'élément situé à `path` (récursif pour un dossier).
    func delete(path: String, sid: String) async throws
    /// Envoie (upload) un fichier local vers le dossier `folderPath` (POST multipart).
    func upload(fileURL: URL, to folderPath: String, sid: String) async throws
    /// Copie (`remove == false`) ou déplace (`remove == true`) `path` vers `destFolder` ; attend la fin.
    func copyMove(path: String, to destFolder: String, remove: Bool, sid: String) async throws
    /// Crée un lien de partage public vers `path` (mot de passe / expiration optionnels) ; renvoie l'URL.
    func createShareLink(path: String, password: String?, dateExpired: String?, sid: String) async throws -> String
    /// Liste les liens de partage existants.
    func listShareLinks(sid: String) async throws -> [SharingLink]
    /// Supprime (révoque) le lien de partage `id`.
    func deleteShareLink(id: String, sid: String) async throws
    func logout(sid: String) async throws
}

@MainActor
final class DSMClient: DSMClientProtocol {
    private static let authAPI = "SYNO.API.Auth"
    private static let systemInfoAPI = "SYNO.DSM.Info"
    private static let fileStationListAPI = "SYNO.FileStation.List"
    private static let fileStationDownloadAPI = "SYNO.FileStation.Download"
    private static let fileStationCreateFolderAPI = "SYNO.FileStation.CreateFolder"
    private static let fileStationRenameAPI = "SYNO.FileStation.Rename"
    private static let fileStationDeleteAPI = "SYNO.FileStation.Delete"
    private static let fileStationUploadAPI = "SYNO.FileStation.Upload"
    private static let fileStationCopyMoveAPI = "SYNO.FileStation.CopyMove"
    private static let fileStationSharingAPI = "SYNO.FileStation.Sharing"

    /// Nom de session applicatif ; réutilisé au logout.
    private static let sessionName = "DSMAccess"

    private let endpoint: DSMEndpoint
    private let session: URLSession
    private let trustDelegate: ServerTrustDelegate

    /// Cache des chemins/versions d'API découverts via SYNO.API.Info.
    private var apiPaths: [String: APIInfoEntry] = [:]

    init(endpoint: DSMEndpoint) {
        self.endpoint = endpoint
        let delegate = ServerTrustDelegate(trustedHost: endpoint.host)
        self.trustDelegate = delegate
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - API publiques

    func apiInfo(for apis: [String]) async throws -> [String: APIInfoEntry] {
        let query = [
            "api": "SYNO.API.Info",
            "version": "1",
            "method": "query",
            "query": apis.joined(separator: ","),
        ]
        let resp = try await get(cgi: "query.cgi", query: query, as: [String: APIInfoEntry].self)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        // On mémorise les chemins pour la durée de vie du client.
        apiPaths.merge(data) { _, new in new }
        return data
    }

    func login(account: String, password: String,
               otpCode: String?, deviceID: String?,
               rememberDevice: Bool) async throws -> LoginResult {
        try await ensurePaths(for: [Self.authAPI, Self.systemInfoAPI])

        var query: [String: String] = [
            "api": "SYNO.API.Auth",
            "version": "6",
            "method": "login",
            "account": account,
            "passwd": password,
            "session": Self.sessionName,
            "format": "sid",
        ]
        if let otpCode, !otpCode.isEmpty {
            query["otp_code"] = otpCode
        }
        if let deviceID, !deviceID.isEmpty {
            query["device_id"] = deviceID
        }
        if rememberDevice {
            query["enable_device_token"] = "yes"
            query["device_name"] = "DSM Access (Mac)"
        }

        let resp = try await get(cgi: path(for: Self.authAPI), query: query, as: LoginResult.self)
        if resp.success, let data = resp.data {
            return data
        }
        switch resp.error?.code {
        case 400: throw DSMError.invalidCredentials
        case 401: throw DSMError.accountDisabled
        case 402: throw DSMError.permissionDenied
        case 403: throw DSMError.needsOTP
        case 404: throw DSMError.badOTP
        case 406: throw DSMError.otpEnforced
        case let code?: throw DSMError.apiError(code: code)
        case nil: throw DSMError.invalidResponse
        }
    }

    func systemInfo(sid: String) async throws -> SystemInfo {
        try await ensurePaths(for: [Self.systemInfoAPI])
        let query = [
            "api": "SYNO.DSM.Info",
            "version": "2",
            "method": "getinfo",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.systemInfoAPI), query: query, as: SystemInfo.self)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data
    }

    func listShares(sid: String) async throws -> [FileStationItem] {
        try await ensurePaths(for: [Self.fileStationListAPI])
        let query = [
            "api": "SYNO.FileStation.List",
            "version": "2",
            "method": "list_share",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.fileStationListAPI), query: query, as: FileStationShares.self)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data.shares
    }

    func list(folderPath: String, sid: String) async throws -> [FileStationItem] {
        try await ensurePaths(for: [Self.fileStationListAPI])
        let query = [
            "api": "SYNO.FileStation.List",
            "version": "2",
            "method": "list",
            "folder_path": folderPath,
            // Tableau JSON attendu par DSM : réclame taille, dates et type pour chaque entrée.
            "additional": "[\"size\",\"time\",\"type\"]",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.fileStationListAPI), query: query, as: FileStationFiles.self)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data.files
    }

    func downloadFile(path: String, sid: String, to destination: URL) async throws {
        try await ensurePaths(for: [Self.fileStationDownloadAPI])
        let query = [
            "api": "SYNO.FileStation.Download",
            "version": "2",
            "method": "download",
            "path": path,
            "mode": "download",
            "_sid": sid,
        ]
        let url = try makeURL(cgi: self.path(for: Self.fileStationDownloadAPI), query: query)

        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await session.download(from: url)
        } catch let error as URLError {
            throw DSMError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DSMError.invalidResponse
        }
        // DSM peut répondre par une erreur JSON (statut 200) au lieu du binaire attendu
        // (chemin invalide, droits insuffisants…). On la détecte via le type MIME.
        if let mime = response.mimeType, mime.contains("json") {
            let data = (try? Data(contentsOf: tempURL)) ?? Data()
            if let resp = try? JSONDecoder().decode(DSMResponse<EmptyData>.self, from: data), !resp.success {
                throw DSMError.apiError(code: resp.error?.code ?? -1)
            }
            throw DSMError.invalidResponse
        }

        // Déplace le fichier temporaire vers l'emplacement choisi (écrase s'il existe déjà).
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempURL, to: destination)
    }

    func createFolder(in folderPath: String, name: String, sid: String) async throws {
        try await ensurePaths(for: [Self.fileStationCreateFolderAPI])
        let query = [
            "api": "SYNO.FileStation.CreateFolder",
            "version": "2",
            "method": "create",
            "folder_path": folderPath,
            "name": name,
            "_sid": sid,
        ]
        let resp = try await get(cgi: self.path(for: Self.fileStationCreateFolderAPI), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func rename(path: String, to name: String, sid: String) async throws {
        try await ensurePaths(for: [Self.fileStationRenameAPI])
        let query = [
            "api": "SYNO.FileStation.Rename",
            "version": "2",
            "method": "rename",
            "path": path,
            "name": name,
            "_sid": sid,
        ]
        let resp = try await get(cgi: self.path(for: Self.fileStationRenameAPI), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func delete(path: String, sid: String) async throws {
        try await ensurePaths(for: [Self.fileStationDeleteAPI])
        let query = [
            "api": "SYNO.FileStation.Delete",
            "version": "2",
            "method": "delete",
            "path": path,
            "recursive": "true",
            "_sid": sid,
        ]
        let resp = try await get(cgi: self.path(for: Self.fileStationDeleteAPI), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func upload(fileURL: URL, to folderPath: String, sid: String) async throws {
        try await ensurePaths(for: [Self.fileStationUploadAPI])
        let url = try makeURL(cgi: self.path(for: Self.fileStationUploadAPI), query: [
            "api": "SYNO.FileStation.Upload",
            "version": "2",
            "method": "upload",
            "_sid": sid,
        ])

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let boundary = "Boundary-\(UUID().uuidString)"

        // Corps multipart : les champs texte d'abord, la partie fichier EN DERNIER (exigence DSM).
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        // DSM (erreur 119 sinon) exige les paramètres de routage AUSSI dans le corps multipart,
        // pas seulement dans l'URL — on les redonne donc ici.
        appendField("api", "SYNO.FileStation.Upload")
        appendField("version", "2")
        appendField("method", "upload")
        appendField("_sid", sid)
        // NB : un NAS avec protection CSRF activée exigerait en plus un SynoToken (récupéré au
        // login via enable_syno_token=yes, à joindre à TOUTES les requêtes) — non nécessaire ici.
        appendField("path", folderPath)
        appendField("create_parents", "true")
        appendField("overwrite", "false")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body)
        } catch let error as URLError {
            throw DSMError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DSMError.invalidResponse
        }
        let decoded: DSMResponse<EmptyData>
        do {
            decoded = try JSONDecoder().decode(DSMResponse<EmptyData>.self, from: data)
        } catch {
            throw DSMError.decoding
        }
        guard decoded.success else {
            throw DSMError.apiError(code: decoded.error?.code ?? -1)
        }
    }

    func copyMove(path: String, to destFolder: String, remove: Bool, sid: String) async throws {
        try await ensurePaths(for: [Self.fileStationCopyMoveAPI])
        let cgi = self.path(for: Self.fileStationCopyMoveAPI)

        // Lance la tâche (asynchrone côté DSM) et récupère son identifiant.
        let startResp = try await get(cgi: cgi, query: [
            "api": "SYNO.FileStation.CopyMove",
            "version": "3",
            "method": "start",
            "path": path,
            "dest_folder_path": destFolder,
            "overwrite": "false",
            "remove_src": remove ? "true" : "false",
            "_sid": sid,
        ], as: CopyMoveTask.self)
        guard startResp.success, let task = startResp.data else {
            throw DSMError.apiError(code: startResp.error?.code ?? -1)
        }

        // Poll le statut jusqu'à la fin (garde-fou ≈ 5 min).
        for _ in 0..<600 {
            let statusResp = try await get(cgi: cgi, query: [
                "api": "SYNO.FileStation.CopyMove",
                "version": "3",
                "method": "status",
                "taskid": task.taskid,
                "_sid": sid,
            ], as: CopyMoveStatus.self)
            guard statusResp.success, let status = statusResp.data else {
                throw DSMError.apiError(code: statusResp.error?.code ?? -1)
            }
            if status.finished { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw DSMError.network(String(localized: "Délai dépassé."))
    }

    func createShareLink(path: String, password: String?, dateExpired: String?, sid: String) async throws -> String {
        try await ensurePaths(for: [Self.fileStationSharingAPI])
        var query = [
            "api": "SYNO.FileStation.Sharing",
            "version": "3",
            "method": "create",
            // DSM attend le chemin dans un tableau JSON.
            "path": "[\"\(path)\"]",
            "_sid": sid,
        ]
        if let password, !password.isEmpty { query["password"] = password }
        if let dateExpired, !dateExpired.isEmpty { query["date_expired"] = dateExpired }
        let resp = try await get(cgi: self.path(for: Self.fileStationSharingAPI), query: query, as: SharingLinks.self)
        guard resp.success, let url = resp.data?.links.first?.url else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return url
    }

    func listShareLinks(sid: String) async throws -> [SharingLink] {
        try await ensurePaths(for: [Self.fileStationSharingAPI])
        let resp = try await get(cgi: self.path(for: Self.fileStationSharingAPI), query: [
            "api": "SYNO.FileStation.Sharing",
            "version": "3",
            "method": "list",
            "_sid": sid,
        ], as: SharingLinks.self)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data.links
    }

    func deleteShareLink(id: String, sid: String) async throws {
        try await ensurePaths(for: [Self.fileStationSharingAPI])
        let resp = try await get(cgi: self.path(for: Self.fileStationSharingAPI), query: [
            "api": "SYNO.FileStation.Sharing",
            "version": "3",
            "method": "delete",
            "id": id,
            "_sid": sid,
        ], as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func logout(sid: String) async throws {
        let query = [
            "api": "SYNO.API.Auth",
            "version": "6",
            "method": "logout",
            "session": Self.sessionName,
            "_sid": sid,
        ]
        _ = try? await get(cgi: path(for: Self.authAPI), query: query, as: EmptyData.self)
    }

    // MARK: - Internes

    /// S'assure que les chemins des API demandées sont connus (interroge SYNO.API.Info si besoin).
    private func ensurePaths(for apis: [String]) async throws {
        let missing = apis.filter { apiPaths[$0] == nil }
        guard !missing.isEmpty else { return }
        _ = try await apiInfo(for: missing)
    }

    /// Chemin CGI d'une API (replié sur entry.cgi si non découvert).
    private func path(for api: String) -> String {
        apiPaths[api]?.path ?? "entry.cgi"
    }

    /// Exécute un GET sur /webapi/<cgi> et décode l'enveloppe DSMResponse<T>.
    private func get<T: Decodable>(cgi: String, query: [String: String], as type: T.Type) async throws -> DSMResponse<T> {
        let url = try makeURL(cgi: cgi, query: query)
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw DSMError.invalidResponse
            }
            do {
                return try JSONDecoder().decode(DSMResponse<T>.self, from: data)
            } catch {
                throw DSMError.decoding
            }
        } catch let error as DSMError {
            throw error
        } catch let error as URLError {
            throw DSMError.network(error.localizedDescription)
        }
    }

    /// Construit l'URL /webapi/<cgi> avec un encodage strict des paramètres
    /// (les mots de passe peuvent contenir +, /, =, espaces…).
    private func makeURL(cgi: String, query: [String: String]) throws -> URL {
        var comps = URLComponents()
        comps.scheme = endpoint.scheme
        comps.host = endpoint.host
        comps.port = endpoint.port
        comps.path = "/webapi/" + cgi
        comps.percentEncodedQueryItems = query.map {
            URLQueryItem(name: Self.encode($0.key), value: Self.encode($0.value))
        }
        guard let url = comps.url else { throw DSMError.invalidEndpoint }
        return url
    }

    private static let queryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? value
    }
}
