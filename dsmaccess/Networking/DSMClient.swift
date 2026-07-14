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
    /// Versions disponibles au catalogue (SYNO.Core.Package.Server), indexées par identifiant
    /// minuscule — pour détecter les mises à jour en comparant avec l'installé.
    func availablePackageVersions(sid: String) async throws -> [String: String]
    /// Démarre (start) ou arrête (stop) un paquet installé (SYNO.Core.Package.Control).
    func setPackageRunning(id: String, running: Bool, sid: String) async throws
    /// Désinstalle un paquet installé (SYNO.Core.Package.Uninstallation).
    func uninstallPackage(id: String, sid: String) async throws
    /// Réglages globaux du Centre de paquets (SYNO.Core.Package.Setting).
    func packageSettings(sid: String) async throws -> PackageSettings
    func setPackageSettings(_ settings: PackageSettings, sid: String) async throws
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

    /// Nom de session applicatif ; réutilisé au logout.
    private static let sessionName = "DSMAccess"

    private let endpoint: DSMEndpoint
    private let session: URLSession
    private let trustDelegate: ServerTrustDelegate
    let transport: DSMTransport
    let authentication: DSMAuthenticationService
    let system: DSMSystemService
    let fileStation: DSMFileStationService

    /// Cache des chemins/versions d'API découverts via SYNO.API.Info.
    private var apiPaths: [String: APIInfoEntry] = [:]

    init(endpoint: DSMEndpoint) {
        self.endpoint = endpoint
        let transport = DSMTransport(endpoint: endpoint)
        self.transport = transport
        self.authentication = DSMAuthenticationService(transport: transport)
        self.system = DSMSystemService(transport: transport)
        self.fileStation = DSMFileStationService(transport: transport)
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
        try await authentication.login(
            account: account,
            password: password,
            otpCode: otpCode,
            deviceID: deviceID,
            rememberDevice: rememberDevice
        )
    }

    func systemInfo(sid: String) async throws -> SystemInfo {
        try await system.information()
    }

    func listShares(sid: String) async throws -> [FileStationItem] {
        try await fileStation.shares()
    }

    func list(folderPath: String, sid: String) async throws -> [FileStationItem] {
        try await fileStation.items(in: folderPath)
    }

    func downloadFile(path: String, sid: String, to destination: URL) async throws {
        try await fileStation.download(path: path, to: destination)
    }

    func createFolder(in folderPath: String, name: String, sid: String) async throws {
        try await fileStation.createFolder(in: folderPath, name: name)
    }

    func rename(path: String, to name: String, sid: String) async throws {
        try await fileStation.rename(path: path, to: name)
    }

    func delete(path: String, sid: String) async throws {
        try await fileStation.delete(path: path)
    }

    func upload(fileURL: URL, to folderPath: String, sid: String) async throws {
        try await fileStation.upload(fileURL: fileURL, to: folderPath)
    }

    func copyMove(path: String, to destFolder: String, remove: Bool, sid: String) async throws {
        try await fileStation.copyMove(path: path, to: destFolder, removeSource: remove)
    }

    func createShareLink(path: String, password: String?, dateExpired: String?, sid: String) async throws -> String {
        try await fileStation.createShareLink(path: path, password: password, expirationDate: dateExpired)
    }

    func listShareLinks(sid: String) async throws -> [SharingLink] {
        try await fileStation.shareLinks()
    }

    func deleteShareLink(id: String, sid: String) async throws {
        try await fileStation.deleteShareLink(id: id)
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
        let resp = try await get(cgi: path(for: Self.storageAPI), query: query, as: StorageInfo.self)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data
    }

    func resourceUsage(sid: String) async throws -> ResourceUsage {
        try await system.resourceUsage()
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
        let resp = try await get(cgi: path(for: Self.shareAPI), query: query, as: ShareList.self)
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
        let resp = try await get(cgi: path(for: service.api), query: query, as: FileServiceStatus.self)
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
        let resp = try await get(cgi: path(for: Self.packageAPI), query: query, as: PackageList.self)
        guard resp.success, let data = resp.data else {
            throw DSMError.apiError(code: resp.error?.code ?? -1)
        }
        return data.packages ?? []
    }

    func availablePackageVersions(sid: String) async throws -> [String: String] {
        try await ensurePaths(for: [Self.packageServerAPI])
        let version = apiPaths[Self.packageServerAPI]?.maxVersion ?? 2
        var versions: [String: String] = [:]
        // Deux sources : catalogue officiel Synology (blloadothers=false) puis tiers-parti (true).
        // On lit le cache du NAS (blforcerefresh=false) pour rester rapide.
        for loadOthers in ["false", "true"] {
            let query = [
                "api": "SYNO.Core.Package.Server",
                "version": String(version),
                "method": "list",
                "blforcerefresh": "false",
                "blloadothers": loadOthers,
                "_sid": sid,
            ]
            guard let resp = try? await get(cgi: path(for: Self.packageServerAPI), query: query, as: ServerPackageList.self),
                  resp.success, let list = resp.data?.packages else { continue }
            for package in list {
                if let id = package.id?.lowercased(), let ver = package.version {
                    versions[id] = ver
                }
            }
        }
        return versions
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
        let resp = try await get(cgi: path(for: Self.packageSettingAPI), query: query, as: PackageSettings.self)
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

    func logout(sid: String) async throws {
        await authentication.logout()
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
            throw error.code == .cancelled ? DSMError.cancelled : DSMError.network(error.localizedDescription)
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
