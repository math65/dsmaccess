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
    /// État du stockage (volumes + disques), via le Gestionnaire de stockage DSM.
    func storageInfo(sid: String) async throws -> StorageInfo
    /// Mesures instantanées de ressources (processeur, mémoire, réseau).
    func resourceUsage(sid: String) async throws -> ResourceUsage
    /// Liste les dossiers partagés du NAS (SYNO.Core.Share).
    func listSharedFolders(sid: String) async throws -> [SharedFolder]
    /// Crée un dossier partagé `name` sur `volumePath` (ex. « /volume1 »).
    func createSharedFolder(name: String, volumePath: String, description: String, sid: String) async throws
    /// Supprime le dossier partagé `name` — et TOUT son contenu.
    func deleteSharedFolder(name: String, sid: String) async throws
    /// État d'activation d'un service de fichiers (SMB, NFS…) ; nil si l'info est absente de la réponse.
    func fileServiceEnabled(_ service: FileService, sid: String) async throws -> Bool?
    /// Active ou désactive un service de fichiers.
    func setFileService(_ service: FileService, enabled: Bool, sid: String) async throws
    /// Liste les paquets installés (SYNO.Core.Package).
    func listPackages(sid: String) async throws -> [PackageInfo]
    /// Mises à jour disponibles au catalogue (SYNO.Core.Package.Server), indexées par identifiant
    /// minuscule — version cible + métadonnées de téléchargement pour les appliquer.
    func availablePackageUpdates(sid: String) async throws -> [String: PackageUpdate]
    /// Applique la mise à jour d'un paquet déjà installé (SYNO.Core.Package.Installation) :
    /// télécharge le .spk puis lance l'upgrade. Opération mutante, non idempotente.
    func upgradePackage(_ update: PackageUpdate, sid: String) async throws
    /// Démarre (start) ou arrête (stop) un paquet installé (SYNO.Core.Package.Control).
    func setPackageRunning(id: String, running: Bool, sid: String) async throws
    /// Désinstalle un paquet installé (SYNO.Core.Package.Uninstallation).
    func uninstallPackage(id: String, sid: String) async throws
    /// Réglages globaux du Centre de paquets (SYNO.Core.Package.Setting).
    func packageSettings(sid: String) async throws -> PackageSettings
    func setPackageSettings(_ settings: PackageSettings, sid: String) async throws
    /// Configuration réseau du NAS (identité, passerelle, DNS) via SYNO.Core.Network.
    func networkInfo(sid: String) async throws -> NetworkInfo
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
    private static let storageAPI = "SYNO.Storage.CGI.Storage"
    private static let utilizationAPI = "SYNO.Core.System.Utilization"
    private static let shareAPI = "SYNO.Core.Share"
    private static let packageAPI = "SYNO.Core.Package"
    private static let packageServerAPI = "SYNO.Core.Package.Server"
    private static let packageControlAPI = "SYNO.Core.Package.Control"
    private static let packageUninstallAPI = "SYNO.Core.Package.Uninstallation"
    private static let packageSettingAPI = "SYNO.Core.Package.Setting"
    private static let packageInstallationAPI = "SYNO.Core.Package.Installation"
    private static let networkAPI = "SYNO.Core.Network"

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
        let resp = try await get(cgi: "query.cgi", query: query, as: [String: APIInfoEntry].self, retryOnTimeout: true)
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

        let resp = try await get(cgi: path(for: Self.authAPI), query: query, as: LoginResult.self, retryOnTimeout: true)
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
        let resp = try await get(cgi: path(for: Self.systemInfoAPI), query: query, as: SystemInfo.self, retryOnTimeout: true)
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
        let resp = try await get(cgi: path(for: Self.fileStationListAPI), query: query, as: FileStationShares.self, retryOnTimeout: true)
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
        let resp = try await get(cgi: path(for: Self.fileStationListAPI), query: query, as: FileStationFiles.self, retryOnTimeout: true)
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
            throw error.code == .cancelled ? DSMError.cancelled : DSMError.network(error.localizedDescription)
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
            throw error.code == .cancelled ? DSMError.cancelled : DSMError.network(error.localizedDescription)
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
        ], as: SharingLinks.self, retryOnTimeout: true)
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

    func storageInfo(sid: String) async throws -> StorageInfo {
        try await ensurePaths(for: [Self.storageAPI])
        // API non documentée : on utilise la version maximale découverte via SYNO.API.Info.
        let version = apiPaths[Self.storageAPI]?.maxVersion ?? 1
        let query = [
            "api": "SYNO.Storage.CGI.Storage",
            "version": String(version),
            "method": "load_info",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.storageAPI), query: query, as: StorageInfo.self, retryOnTimeout: true)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data
    }

    func resourceUsage(sid: String) async throws -> ResourceUsage {
        try await ensurePaths(for: [Self.utilizationAPI])
        // API non documentée : on utilise la version maximale découverte via SYNO.API.Info.
        let version = apiPaths[Self.utilizationAPI]?.maxVersion ?? 1
        let query = [
            "api": "SYNO.Core.System.Utilization",
            "version": String(version),
            "method": "get",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.utilizationAPI), query: query, as: ResourceUsage.self, retryOnTimeout: true)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data
    }

    func listSharedFolders(sid: String) async throws -> [SharedFolder] {
        try await ensurePaths(for: [Self.shareAPI])
        // API non documentée : on utilise la version maximale découverte via SYNO.API.Info.
        let version = apiPaths[Self.shareAPI]?.maxVersion ?? 1
        let query = [
            "api": "SYNO.Core.Share",
            "version": String(version),
            "method": "list",
            // Champs supplémentaires (tableau JSON) ; valeurs tirées du client officiel Synology.
            "additional": "[\"recyclebin\",\"share_quota\"]",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.shareAPI), query: query, as: ShareList.self, retryOnTimeout: true)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data.shares ?? []
    }

    func createSharedFolder(name: String, volumePath: String, description: String, sid: String) async throws {
        try await ensurePaths(for: [Self.shareAPI])
        let version = apiPaths[Self.shareAPI]?.maxVersion ?? 1
        // `shareinfo` = objet JSON décrivant le partage (forme du client officiel synology-csi).
        let info = ShareCreateInfo(name: name, volPath: volumePath, desc: description)
        let shareInfoJSON = String(decoding: try JSONEncoder().encode(info), as: UTF8.self)
        let query = [
            "api": "SYNO.Core.Share",
            "version": String(version),
            "method": "create",
            // Le client officiel Synology quote le nom en JSON (à recaler si le NAS refuse).
            "name": "\"\(name)\"",
            "shareinfo": shareInfoJSON,
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.shareAPI), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func deleteSharedFolder(name: String, sid: String) async throws {
        try await ensurePaths(for: [Self.shareAPI])
        let version = apiPaths[Self.shareAPI]?.maxVersion ?? 1
        let query = [
            "api": "SYNO.Core.Share",
            "version": String(version),
            "method": "delete",
            // DSM attend un tableau JSON de noms (client officiel : name=["x"]).
            "name": "[\"\(name)\"]",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.shareAPI), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func fileServiceEnabled(_ service: FileService, sid: String) async throws -> Bool? {
        try await ensurePaths(for: [service.api])
        // API non documentée : on utilise la version maximale découverte via SYNO.API.Info.
        let version = apiPaths[service.api]?.maxVersion ?? 1
        let query = [
            "api": service.api,
            "version": String(version),
            "method": "get",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: service.api), query: query, as: FileServiceStatus.self, retryOnTimeout: true)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data.enabled(for: service)
    }

    func setFileService(_ service: FileService, enabled: Bool, sid: String) async throws {
        try await ensurePaths(for: [service.api])
        let version = apiPaths[service.api]?.maxVersion ?? 1
        let query = [
            "api": service.api,
            "version": String(version),
            "method": "set",
            service.enableKey: enabled ? "true" : "false",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: service.api), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func listPackages(sid: String) async throws -> [PackageInfo] {
        try await ensurePaths(for: [Self.packageAPI])
        // API non documentée : on utilise la version maximale découverte via SYNO.API.Info.
        let version = apiPaths[Self.packageAPI]?.maxVersion ?? 2
        let query = [
            "api": "SYNO.Core.Package",
            "version": String(version),
            "method": "list",
            // Champs supplémentaires (tableau JSON) : état, version, pilotabilité et désinstallabilité.
            "additional": "[\"status\",\"installed_info\",\"startable\",\"ctl_uninstall\",\"is_uninstall_pages\"]",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.packageAPI), query: query, as: PackageList.self, retryOnTimeout: true)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data.packages ?? []
    }

    func availablePackageUpdates(sid: String) async throws -> [String: PackageUpdate] {
        try await ensurePaths(for: [Self.packageServerAPI])
        let version = apiPaths[Self.packageServerAPI]?.maxVersion ?? 2
        // Périmètre « officiels d'abord » : on ne charge que le catalogue officiel Synology
        // (blloadothers=false), c.-à-d. les paquets signés (source == "syno").
        // On lit le cache du NAS (blforcerefresh=false) pour rester rapide.
        let query = [
            "api": "SYNO.Core.Package.Server",
            "version": String(version),
            "method": "list",
            "blforcerefresh": "false",
            "blloadothers": "false",
            "_sid": sid,
        ]
        guard let resp = try? await get(cgi: path(for: Self.packageServerAPI), query: query, as: ServerPackageList.self, retryOnTimeout: true),
              resp.success, let list = resp.data?.packages else { return [:] }
        var updates: [String: PackageUpdate] = [:]
        for package in list {
            // On ne retient que les entrées complètes (lien + checksum + taille) : ce sont
            // les seules qu'on pourra réellement télécharger puis mettre à jour.
            guard let rawID = package.id,
                  let ver = package.version,
                  let link = package.link,
                  let md5 = package.md5,
                  let size = package.size else { continue }
            updates[rawID.lowercased()] = PackageUpdate(
                id: rawID, version: ver, link: link, md5: md5, size: size,
                isSyno: package.source == "syno", beta: package.beta ?? false, type: package.type ?? 0)
        }
        return updates
    }

    func upgradePackage(_ update: PackageUpdate, sid: String) async throws {
        try await ensurePaths(for: [Self.packageInstallationAPI])
        // Flux calqué sur le Package Center web (source de vérité, code JS observé) : l'upgrade se
        // fait en UN SEUL appel « upgrade » qui reçoit directement l'URL du .spk, le checksum, la
        // taille et les drapeaux du paquet. DSM télécharge puis installe côté serveur ; on suit
        // l'avancement via « status ». (version 1, comme le web.)
        let version = String(apiPaths[Self.packageInstallationAPI]?.minVersion ?? 1)
        let cgi = path(for: Self.packageInstallationAPI)

        let startResp = try await get(cgi: cgi, query: [
            "api": Self.packageInstallationAPI,
            "version": version,
            "method": "upgrade",
            "name": update.id,
            "is_syno": update.isSyno ? "true" : "false",
            "beta": update.beta ? "true" : "false",
            "url": update.link,
            "checksum": update.md5,
            "filesize": String(update.size),
            "type": String(update.type),
            "blqinst": "false",
            "operation": "upgrade",
            "_sid": sid,
        ], as: PackageInstallTask.self)
        guard startResp.success, let task = startResp.data else {
            throw DSMError.apiError(code: startResp.error?.code ?? -1)
        }

        // Suit le téléchargement + l'installation (côté NAS) jusqu'à la fin. Le web sonde toutes
        // les 1,2 s ; garde-fou large car un gros paquet peut prendre plusieurs minutes.
        for _ in 0..<900 {
            try await Task.sleep(for: .milliseconds(1200))
            let statusResp = try await get(cgi: cgi, query: [
                "api": Self.packageInstallationAPI,
                "version": version,
                "method": "status",
                "task_id": task.taskid,
                "_sid": sid,
            ], as: PackageInstallStatus.self)
            guard statusResp.success, let status = statusResp.data else {
                throw DSMError.apiError(code: statusResp.error?.code ?? -1)
            }
            if status.finished == true { return }
        }
        throw DSMError.network(String(localized: "La mise à jour a expiré."))
    }

    func setPackageRunning(id: String, running: Bool, sid: String) async throws {
        try await ensurePaths(for: [Self.packageControlAPI])
        // API non documentée : on utilise la version maximale découverte via SYNO.API.Info.
        let version = apiPaths[Self.packageControlAPI]?.maxVersion ?? 1
        let query = [
            "api": Self.packageControlAPI,
            "version": String(version),
            "method": running ? "start" : "stop",
            "id": id,
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.packageControlAPI), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func uninstallPackage(id: String, sid: String) async throws {
        try await ensurePaths(for: [Self.packageUninstallAPI])
        // API non documentée : on utilise la version maximale découverte via SYNO.API.Info.
        let version = apiPaths[Self.packageUninstallAPI]?.maxVersion ?? 1
        let query = [
            "api": Self.packageUninstallAPI,
            "version": String(version),
            "method": "uninstall",
            "id": id,
            // dsm_apps vide : désinstallation standard, réglages par défaut du paquet.
            "dsm_apps": "",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.packageUninstallAPI), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func packageSettings(sid: String) async throws -> PackageSettings {
        try await ensurePaths(for: [Self.packageSettingAPI])
        let version = apiPaths[Self.packageSettingAPI]?.maxVersion ?? 1
        let query = [
            "api": Self.packageSettingAPI,
            "version": String(version),
            "method": "get",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.packageSettingAPI), query: query, as: PackageSettings.self, retryOnTimeout: true)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data
    }

    func setPackageSettings(_ settings: PackageSettings, sid: String) async throws {
        try await ensurePaths(for: [Self.packageSettingAPI])
        let version = apiPaths[Self.packageSettingAPI]?.maxVersion ?? 1
        func flag(_ value: Bool) -> String { value ? "true" : "false" }
        // On renvoie l'objet complet : default_vol et trust_level sont préservés tels quels.
        let query = [
            "api": Self.packageSettingAPI,
            "version": String(version),
            "method": "set",
            "enable_autoupdate": flag(settings.enableAutoupdate),
            "autoupdateall": flag(settings.autoupdateAll),
            "autoupdateimportant": flag(settings.autoupdateImportant),
            "enable_dsm": flag(settings.enableDsm),
            "enable_email": flag(settings.enableEmail),
            "default_vol": settings.defaultVol,
            "trust_level": String(settings.trustLevel),
            "update_channel": settings.updateChannelBeta ? "beta" : "stable",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.packageSettingAPI), query: query, as: EmptyData.self)
        guard resp.success else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
    }

    func networkInfo(sid: String) async throws -> NetworkInfo {
        try await ensurePaths(for: [Self.networkAPI])
        // API non documentée : on utilise la version maximale découverte via SYNO.API.Info.
        let version = apiPaths[Self.networkAPI]?.maxVersion ?? 1
        let query = [
            "api": "SYNO.Core.Network",
            "version": String(version),
            "method": "get",
            "_sid": sid,
        ]
        let resp = try await get(cgi: path(for: Self.networkAPI), query: query, as: NetworkInfo.self, retryOnTimeout: true)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data
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
    ///
    /// `retryOnTimeout` autorise UN nouvel essai silencieux si la requête expire : la toute
    /// première requête d'une session paie la résolution du nom (mDNS/.local) et l'établissement
    /// TCP/TLS « à froid » et peut dépasser le délai ; le nouvel essai profite du cache DNS système.
    /// À n'activer que sur des requêtes idempotentes (lectures, login) — jamais sur une mutation,
    /// où un timeout survenu APRÈS l'action côté NAS ferait exécuter l'opération deux fois.
    private func get<T: Decodable>(cgi: String, query: [String: String], as type: T.Type,
                                   retryOnTimeout: Bool = false) async throws -> DSMResponse<T> {
        let url = try makeURL(cgi: cgi, query: query)
        do {
            do {
                return try await send(url: url, as: type)
            } catch let error as URLError where retryOnTimeout && error.code == .timedOut {
                try? await Task.sleep(for: .milliseconds(500))
                return try await send(url: url, as: type)
            }
        } catch let error as DSMError {
            throw error
        } catch let error as URLError {
            throw error.code == .cancelled ? DSMError.cancelled : DSMError.network(error.localizedDescription)
        }
    }

    /// Un aller-retour HTTP + décodage, sans logique de retry. Laisse remonter l'`URLError` brute
    /// (pour que `get` puisse détecter un timeout) ; convertit seulement les échecs de décodage.
    private func send<T: Decodable>(url: URL, as type: T.Type) async throws -> DSMResponse<T> {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DSMError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(DSMResponse<T>.self, from: data)
        } catch {
            throw DSMError.decoding
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
