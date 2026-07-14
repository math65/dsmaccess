//
//  DSMClient.swift
//  dsmaccess
//
//  Façade de compatibilité regroupant les services DSM spécialisés.
//

import Foundation

/// Contrat de la façade DSM. Les services concrets partagent un transport unique qui
/// centralise la découverte des API, l'authentification et la gestion des erreurs.
protocol DSMClientProtocol: AnyObject {
    var capabilities: DSMCapabilities { get }
    func discoverCapabilities() async throws -> DSMCapabilities
    func apiInfo(for apis: [String]) async throws -> [String: APIInfoEntry]
    func login(
        account: String,
        password: String,
        otpCode: String?,
        deviceID: String?,
        rememberDevice: Bool
    ) async throws -> LoginResult
    func systemInfo(sid: String) async throws -> SystemInfo
    func listShares(sid: String) async throws -> [FileStationItem]
    func list(folderPath: String, sid: String) async throws -> [FileStationItem]
    func downloadFile(path: String, sid: String, to destination: URL) async throws
    func createFolder(in folderPath: String, name: String, sid: String) async throws
    func rename(path: String, to name: String, sid: String) async throws
    func delete(path: String, sid: String) async throws
    func delete(paths: [String], sid: String) async throws
    func upload(fileURL: URL, to folderPath: String, sid: String) async throws
    func copyMove(path: String, to destFolder: String, remove: Bool, sid: String) async throws
    func copyMove(paths: [String], to destFolder: String, remove: Bool, sid: String) async throws
    func searchFiles(in folderPath: String, matching pattern: String, sid: String) async throws -> [FileStationItem]
    func fileStationFavorites(sid: String) async throws -> [FileStationFavorite]
    func addFileStationFavorite(path: String, name: String, sid: String) async throws
    func removeFileStationFavorite(path: String, sid: String) async throws
    func compress(paths: [String], to destinationPath: String, sid: String) async throws
    func extract(archivePath: String, to destinationFolder: String, sid: String) async throws
    func createShareLink(
        path: String,
        password: String?,
        dateExpired: String?,
        sid: String
    ) async throws -> String
    func listShareLinks(sid: String) async throws -> [SharingLink]
    func deleteShareLink(id: String, sid: String) async throws
    func storageInfo(sid: String) async throws -> StorageInfo
    func resourceUsage(sid: String) async throws -> ResourceUsage
    func listSharedFolders(sid: String) async throws -> [SharedFolder]
    func createSharedFolder(
        name: String,
        volumePath: String,
        description: String,
        sid: String
    ) async throws
    func deleteSharedFolder(name: String, sid: String) async throws
    func fileServiceEnabled(_ service: FileService, sid: String) async throws -> Bool?
    func setFileService(_ service: FileService, enabled: Bool, sid: String) async throws
    func listPackages(sid: String) async throws -> [PackageInfo]
    func availablePackageVersions(sid: String) async throws -> [String: String]
    func setPackageRunning(id: String, running: Bool, sid: String) async throws
    func uninstallPackage(id: String, sid: String) async throws
    func packageSettings(sid: String) async throws -> PackageSettings
    func setPackageSettings(_ settings: PackageSettings, sid: String) async throws
    func logout(sid: String) async throws
}

@MainActor
final class DSMClient: DSMClientProtocol {
    let transport: DSMTransport
    let authentication: DSMAuthenticationService
    let system: DSMSystemService
    let fileStation: DSMFileStationService
    let storage: DSMStorageService
    let shares: DSMShareService
    let fileServiceSettings: DSMFileServiceSettingsService
    let packages: DSMPackageService

    init(endpoint: DSMEndpoint) {
        let transport = DSMTransport(endpoint: endpoint)
        self.transport = transport
        authentication = DSMAuthenticationService(transport: transport)
        system = DSMSystemService(transport: transport)
        fileStation = DSMFileStationService(transport: transport)
        storage = DSMStorageService(transport: transport)
        shares = DSMShareService(transport: transport)
        fileServiceSettings = DSMFileServiceSettingsService(transport: transport)
        packages = DSMPackageService(transport: transport)
    }

    var capabilities: DSMCapabilities { transport.capabilities }

    func discoverCapabilities() async throws -> DSMCapabilities {
        try await transport.discoverAll()
    }

    func apiInfo(for apis: [String]) async throws -> [String: APIInfoEntry] {
        try await transport.discover(apis)
    }

    func login(
        account: String,
        password: String,
        otpCode: String?,
        deviceID: String?,
        rememberDevice: Bool
    ) async throws -> LoginResult {
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

    func delete(paths: [String], sid: String) async throws {
        try await fileStation.delete(paths: paths)
    }

    func upload(fileURL: URL, to folderPath: String, sid: String) async throws {
        try await fileStation.upload(fileURL: fileURL, to: folderPath)
    }

    func copyMove(path: String, to destFolder: String, remove: Bool, sid: String) async throws {
        try await fileStation.copyMove(path: path, to: destFolder, removeSource: remove)
    }

    func copyMove(paths: [String], to destFolder: String, remove: Bool, sid: String) async throws {
        try await fileStation.copyMove(paths: paths, to: destFolder, removeSource: remove)
    }

    func searchFiles(in folderPath: String, matching pattern: String, sid: String) async throws -> [FileStationItem] {
        try await fileStation.search(in: folderPath, matching: pattern)
    }

    func fileStationFavorites(sid: String) async throws -> [FileStationFavorite] {
        try await fileStation.favorites()
    }

    func addFileStationFavorite(path: String, name: String, sid: String) async throws {
        try await fileStation.addFavorite(path: path, name: name)
    }

    func removeFileStationFavorite(path: String, sid: String) async throws {
        try await fileStation.removeFavorite(path: path)
    }

    func compress(paths: [String], to destinationPath: String, sid: String) async throws {
        try await fileStation.compress(paths: paths, to: destinationPath)
    }

    func extract(archivePath: String, to destinationFolder: String, sid: String) async throws {
        try await fileStation.extract(archivePath: archivePath, to: destinationFolder)
    }

    func createShareLink(
        path: String,
        password: String?,
        dateExpired: String?,
        sid: String
    ) async throws -> String {
        try await fileStation.createShareLink(
            path: path,
            password: password,
            expirationDate: dateExpired
        )
    }

    func listShareLinks(sid: String) async throws -> [SharingLink] {
        try await fileStation.shareLinks()
    }

    func deleteShareLink(id: String, sid: String) async throws {
        try await fileStation.deleteShareLink(id: id)
    }

    func storageInfo(sid: String) async throws -> StorageInfo {
        try await storage.information()
    }

    func resourceUsage(sid: String) async throws -> ResourceUsage {
        try await system.resourceUsage()
    }

    func listSharedFolders(sid: String) async throws -> [SharedFolder] {
        try await shares.folders()
    }

    func createSharedFolder(
        name: String,
        volumePath: String,
        description: String,
        sid: String
    ) async throws {
        try await shares.create(name: name, volumePath: volumePath, description: description)
    }

    func deleteSharedFolder(name: String, sid: String) async throws {
        try await shares.delete(name: name)
    }

    func fileServiceEnabled(_ service: FileService, sid: String) async throws -> Bool? {
        try await fileServiceSettings.isEnabled(service)
    }

    func setFileService(_ service: FileService, enabled: Bool, sid: String) async throws {
        try await fileServiceSettings.set(service, enabled: enabled)
    }

    func listPackages(sid: String) async throws -> [PackageInfo] {
        try await packages.installedPackages()
    }

    func availablePackageVersions(sid: String) async throws -> [String: String] {
        try await packages.availableVersions()
    }

    func setPackageRunning(id: String, running: Bool, sid: String) async throws {
        try await packages.setRunning(running, packageID: id)
    }

    func uninstallPackage(id: String, sid: String) async throws {
        try await packages.uninstall(packageID: id)
    }

    func packageSettings(sid: String) async throws -> PackageSettings {
        try await packages.settings()
    }

    func setPackageSettings(_ settings: PackageSettings, sid: String) async throws {
        try await packages.setSettings(settings)
    }

    func logout(sid: String) async throws {
        await authentication.logout()
    }
}
