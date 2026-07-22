//
//  DSMClient.swift
//  dsmaccess
//
//  Façade de session regroupant les services DSM spécialisés.
//

import Foundation

/// Contrat de la façade DSM. Les services concrets partagent un transport unique qui
/// centralise la découverte des API, l'authentification et la gestion des erreurs.
@MainActor
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
    func systemInfo() async throws -> SystemInfo
    func fileStationCapabilities() async throws -> FileStationCapabilities
    func listShares() async throws -> [FileStationItem]
    func listShares(options: FileStationListOptions) async throws -> FileStationPage<FileStationItem>
    func list(folderPath: String) async throws -> [FileStationItem]
    func list(
        folderPath: String,
        options: FileStationListOptions
    ) async throws -> FileStationPage<FileStationItem>
    func fileInformation(paths: [String]) async throws -> [FileStationItem]
    func virtualFolders(
        type: FileStationVirtualFolderType,
        options: FileStationListOptions
    ) async throws -> FileStationPage<FileStationItem>
    func fileThumbnail(
        path: String,
        size: FileStationThumbnailSize,
        rotation: FileStationThumbnailRotation
    ) async throws -> Data
    func downloadFile(path: String, to destination: URL) async throws
    func downloadFile(
        path: String,
        to destination: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws
    func downloadFiles(paths: [String], to destination: URL) async throws
    func downloadFiles(
        paths: [String],
        to destination: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws
    func createFolder(in folderPath: String, name: String) async throws
    func createFolders(
        _ folders: [FileStationFolderCreation],
        forceParentFolders: Bool
    ) async throws -> [FileStationItem]
    func rename(path: String, to name: String) async throws
    func rename(
        _ changes: [FileStationRenameChange],
        searchTaskID: String?
    ) async throws -> [FileStationItem]
    func delete(path: String) async throws
    func delete(paths: [String]) async throws
    func delete(
        paths: [String],
        progress: (FileOperationProgress) -> Void
    ) async throws
    func upload(fileURL: URL, to folderPath: String) async throws
    func upload(
        fileURL: URL,
        to folderPath: String,
        options: FileStationUploadOptions
    ) async throws
    func upload(
        fileURL: URL,
        to folderPath: String,
        options: FileStationUploadOptions,
        progress: @escaping DSMTransferProgressHandler
    ) async throws
    func copyMove(path: String, to destFolder: String, remove: Bool) async throws
    func copyMove(paths: [String], to destFolder: String, remove: Bool) async throws
    func copyMove(
        paths: [String],
        to destFolder: String,
        remove: Bool,
        conflictPolicy: FileConflictPolicy,
        progress: (FileOperationProgress) -> Void
    ) async throws
    func searchFiles(in folderPath: String, matching pattern: String) async throws -> [FileStationItem]
    func searchFiles(
        criteria: FileStationSearchCriteria,
        resultOptions: FileStationSearchResultOptions,
        progress: (FileStationSearchProgress) -> Void
    ) async throws -> [FileStationItem]
    func fileStationFavorites() async throws -> [FileStationFavorite]
    func fileStationFavorites(
        status: FileStationFavoriteStatus,
        offset: Int,
        limit: Int
    ) async throws -> FileStationPage<FileStationFavorite>
    func addFileStationFavorite(path: String, name: String) async throws
    func removeFileStationFavorite(path: String) async throws
    func editFileStationFavorite(path: String, name: String) async throws
    func replaceFileStationFavorites(_ favorites: [FileStationFavorite]) async throws
    func clearBrokenFileStationFavorites() async throws
    func compress(paths: [String], to destinationPath: String) async throws
    func compress(
        paths: [String],
        to destinationPath: String,
        progress: (FileOperationProgress) -> Void
    ) async throws
    func compress(
        paths: [String],
        to destinationPath: String,
        options: FileStationCompressionOptions,
        progress: (FileOperationProgress) -> Void
    ) async throws
    func extract(archivePath: String, to destinationFolder: String) async throws
    func extract(
        archivePath: String,
        to destinationFolder: String,
        progress: (FileOperationProgress) -> Void
    ) async throws
    func extract(
        archivePath: String,
        to destinationFolder: String,
        options: FileStationExtractionOptions,
        progress: (FileOperationProgress) -> Void
    ) async throws
    func archiveItems(
        archivePath: String,
        options: FileStationArchiveListOptions
    ) async throws -> FileStationPage<FileStationArchiveItem>
    func checkFileStationWritePermission(
        in folderPath: String,
        filename: String,
        conflictPolicy: FileConflictPolicy,
        createOnly: Bool
    ) async throws
    func fileStationDirectorySize(
        paths: [String],
        progress: (FileOperationProgress) -> Void
    ) async throws -> FileStationDirectorySize
    func fileStationChecksum(
        path: String,
        progress: (FileOperationProgress) -> Void
    ) async throws -> String
    func fileStationBackgroundTasks() async throws -> [FileStationBackgroundTask]
    func fileStationBackgroundTasks(
        options: FileStationBackgroundTaskListOptions
    ) async throws -> FileStationPage<FileStationBackgroundTask>
    func clearFinishedFileStationBackgroundTasks(taskIDs: [String]) async throws
    func stopFileStationOperation(kind: FileOperationKind, taskID: String) async throws
    func createShareLink(
        path: String,
        password: String?,
        dateExpired: String?
    ) async throws -> String
    func createShareLinks(_ creation: FileStationShareLinkCreation) async throws -> [SharingLink]
    func shareLinkInformation(id: String) async throws -> SharingLink
    func listShareLinks() async throws -> [SharingLink]
    func listShareLinks(
        options: FileStationSharingListOptions
    ) async throws -> FileStationPage<SharingLink>
    func deleteShareLink(id: String) async throws
    func deleteShareLinks(ids: [String]) async throws
    func editShareLinks(ids: [String], changes: FileStationShareLinkChanges) async throws
    func clearInvalidShareLinks() async throws
    func storageInfo() async throws -> StorageInfo
    func resourceUsage() async throws -> ResourceUsage
    func listSharedFolders() async throws -> [SharedFolder]
    func createSharedFolder(
        name: String,
        volumePath: String,
        description: String
    ) async throws
    func deleteSharedFolder(name: String) async throws
    func fileServiceEnabled(_ service: FileService) async throws -> Bool?
    func setFileService(_ service: FileService, enabled: Bool) async throws
    func packageCenterCapabilities() async throws -> PackageCenterCapabilities
    func listPackages() async throws -> [PackageInfo]
    func officialPackageCatalog(forceRefresh: Bool) async throws -> [PackageUpdate]
    func availablePackageUpdates() async throws -> [String: PackageUpdate]
    func upgradePackage(_ update: PackageUpdate) async throws
    func upgradePackage(
        _ update: PackageUpdate,
        progress: (PackageOperationProgress) -> Void
    ) async throws
    func installPackage(
        _ update: PackageUpdate,
        progress: (PackageOperationProgress) -> Void
    ) async throws
    func repairPackage(
        _ update: PackageUpdate,
        installsNewerVersion: Bool,
        progress: (PackageOperationProgress) -> Void
    ) async throws
    func installManualPackage(
        at fileURL: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws -> String
    func setPackageRunning(id: String, running: Bool) async throws
    func uninstallPackage(id: String) async throws
    func packageSettings() async throws -> PackageSettings
    func setPackageSettings(_ settings: PackageSettings) async throws
    func packageSources() async throws -> [PackageSource]
    func addPackageSource(_ source: PackageSource) async throws
    func updatePackageSource(_ source: PackageSource, originalFeed: String) async throws
    func deletePackageSources(feeds: [String]) async throws
    func listUsers() async throws -> [DSMUser]
    func listGroups() async throws -> [DSMGroup]
    func createUser(_ draft: DSMUserDraft) async throws
    func setUser(_ name: String, disabled: Bool) async throws
    func deleteUser(_ name: String) async throws
    func createGroup(_ draft: DSMGroupDraft) async throws
    func deleteGroup(_ name: String) async throws
    func listDownloadTasks() async throws -> [DownloadTask]
    func downloadStatistic() async throws -> DownloadStatistic
    func createDownload(uri: String, destination: String?) async throws
    func pauseDownloads(ids: Set<String>) async throws
    func resumeDownloads(ids: Set<String>) async throws
    func deleteDownloads(ids: Set<String>, forceComplete: Bool) async throws
    func listUSBCopyTasks() async throws -> [USBCopyTask]
    func usbCopyTask(id: Int) async throws -> USBCopyTask
    func createUSBCopyTask(_ task: USBCopyTaskCreation) async throws -> Int
    func setUSBCopyTaskSettings(_ settings: USBCopyTaskSettings) async throws
    func usbCopyFilter(taskID: Int) async throws -> USBCopyFilter
    func setUSBCopyFilter(_ filter: USBCopyFilter, taskID: Int) async throws
    func usbCopyTrigger(for task: USBCopyTask) async throws -> USBCopyTrigger
    func setUSBCopyTrigger(_ trigger: USBCopyTrigger, taskID: Int) async throws
    func usbCopyGlobalSettings() async throws -> USBCopyGlobalSettings
    func setUSBCopyGlobalSettings(_ settings: USBCopyGlobalSettings) async throws
    func usbCopyLogs(
        offset: Int,
        limit: Int,
        filter: USBCopyLogFilter
    ) async throws -> USBCopyLogPage
    func usbCopyAvailableShares() async throws -> [SharedFolder]
    func usbCopyAvailableVolumePaths() async throws -> [String]
    func runUSBCopyTask(id: Int) async throws
    func cancelUSBCopyTask(id: Int) async throws
    func enableUSBCopyTask(id: Int) async throws
    func disableUSBCopyTask(id: Int) async throws
    func deleteUSBCopyTask(id: Int) async throws
    func listVirtualMachines() async throws -> [VirtualMachine]
    func performVirtualMachineAction(
        _ action: VirtualMachinePowerAction,
        guestID: String
    ) async throws
    func listContainers() async throws -> [ContainerItem]
    func performContainerAction(_ action: ContainerAction, name: String) async throws
    func containerLogs(name: String) async throws -> [ContainerLogEntry]
    func listSurveillanceCameras() async throws -> [SurveillanceCamera]
    func setSurveillanceCameras(ids: Set<String>, enabled: Bool) async throws
    func surveillanceSnapshot(cameraID: String) async throws -> Data
    func listSystemLogs() async throws -> [SystemLogEntry]
    func listBlockedAddresses() async throws -> [BlockedAddress]
    func unblockAddress(_ address: String) async throws
    func networkInfo() async throws -> NetworkInfo
    func logout() async throws
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
    let accounts: DSMAccountService
    let downloadStation: DSMDownloadStationService
    let usbCopy: DSMUSBCopyService
    let virtualMachines: DSMVirtualMachineService
    let containers: DSMContainerService
    let surveillance: DSMSurveillanceService
    let logsSecurity: DSMLogSecurityService
    let network: DSMNetworkService

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
        accounts = DSMAccountService(transport: transport)
        downloadStation = DSMDownloadStationService(transport: transport)
        usbCopy = DSMUSBCopyService(transport: transport)
        virtualMachines = DSMVirtualMachineService(transport: transport)
        containers = DSMContainerService(transport: transport)
        surveillance = DSMSurveillanceService(transport: transport)
        logsSecurity = DSMLogSecurityService(transport: transport)
        network = DSMNetworkService(transport: transport)
    }

    var capabilities: DSMCapabilities { transport.capabilities }

    func approveServerCertificate(fingerprint: String) -> Bool {
        transport.approveServerCertificate(fingerprint: fingerprint)
    }

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

    func systemInfo() async throws -> SystemInfo {
        try await system.information()
    }

    func fileStationCapabilities() async throws -> FileStationCapabilities {
        try await fileStation.capabilities()
    }

    func listShares() async throws -> [FileStationItem] {
        try await fileStation.shares()
    }

    func listShares(options: FileStationListOptions) async throws -> FileStationPage<FileStationItem> {
        try await fileStation.shares(options: options)
    }

    func list(folderPath: String) async throws -> [FileStationItem] {
        try await fileStation.items(in: folderPath)
    }

    func list(
        folderPath: String,
        options: FileStationListOptions
    ) async throws -> FileStationPage<FileStationItem> {
        try await fileStation.items(in: folderPath, options: options)
    }

    func fileInformation(paths: [String]) async throws -> [FileStationItem] {
        try await fileStation.itemInformation(paths: paths)
    }

    func virtualFolders(
        type: FileStationVirtualFolderType,
        options: FileStationListOptions
    ) async throws -> FileStationPage<FileStationItem> {
        try await fileStation.virtualFolders(of: type, options: options)
    }

    func fileThumbnail(
        path: String,
        size: FileStationThumbnailSize,
        rotation: FileStationThumbnailRotation
    ) async throws -> Data {
        try await fileStation.thumbnail(path: path, size: size, rotation: rotation)
    }

    func downloadFile(path: String, to destination: URL) async throws {
        try await fileStation.download(path: path, to: destination)
    }

    func downloadFile(
        path: String,
        to destination: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws {
        try await fileStation.download(paths: [path], to: destination, progress: progress)
    }

    func downloadFiles(paths: [String], to destination: URL) async throws {
        try await fileStation.download(paths: paths, to: destination)
    }

    func downloadFiles(
        paths: [String],
        to destination: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws {
        try await fileStation.download(paths: paths, to: destination, progress: progress)
    }

    func createFolder(in folderPath: String, name: String) async throws {
        try await fileStation.createFolder(in: folderPath, name: name)
    }

    func createFolders(
        _ folders: [FileStationFolderCreation],
        forceParentFolders: Bool
    ) async throws -> [FileStationItem] {
        try await fileStation.createFolders(folders, forceParentFolders: forceParentFolders)
    }

    func rename(path: String, to name: String) async throws {
        try await fileStation.rename(path: path, to: name)
    }

    func rename(
        _ changes: [FileStationRenameChange],
        searchTaskID: String?
    ) async throws -> [FileStationItem] {
        try await fileStation.rename(changes, searchTaskID: searchTaskID)
    }

    func delete(path: String) async throws {
        try await fileStation.delete(path: path)
    }

    func delete(paths: [String]) async throws {
        try await fileStation.delete(paths: paths)
    }

    func delete(
        paths: [String],
        progress: (FileOperationProgress) -> Void
    ) async throws {
        try await fileStation.delete(paths: paths, progress: progress)
    }

    func upload(fileURL: URL, to folderPath: String) async throws {
        try await fileStation.upload(fileURL: fileURL, to: folderPath)
    }

    func upload(
        fileURL: URL,
        to folderPath: String,
        options: FileStationUploadOptions
    ) async throws {
        try await fileStation.upload(fileURL: fileURL, to: folderPath, options: options)
    }

    func upload(
        fileURL: URL,
        to folderPath: String,
        options: FileStationUploadOptions,
        progress: @escaping DSMTransferProgressHandler
    ) async throws {
        try await fileStation.upload(
            fileURL: fileURL,
            to: folderPath,
            options: options,
            progress: progress
        )
    }

    func copyMove(path: String, to destFolder: String, remove: Bool) async throws {
        try await fileStation.copyMove(path: path, to: destFolder, removeSource: remove)
    }

    func copyMove(paths: [String], to destFolder: String, remove: Bool) async throws {
        try await fileStation.copyMove(paths: paths, to: destFolder, removeSource: remove)
    }

    func copyMove(
        paths: [String],
        to destFolder: String,
        remove: Bool,
        conflictPolicy: FileConflictPolicy,
        progress: (FileOperationProgress) -> Void
    ) async throws {
        try await fileStation.copyMove(
            paths: paths,
            to: destFolder,
            removeSource: remove,
            conflictPolicy: conflictPolicy,
            progress: progress
        )
    }

    func searchFiles(in folderPath: String, matching pattern: String) async throws -> [FileStationItem] {
        try await fileStation.search(in: folderPath, matching: pattern)
    }

    func searchFiles(
        criteria: FileStationSearchCriteria,
        resultOptions: FileStationSearchResultOptions,
        progress: (FileStationSearchProgress) -> Void
    ) async throws -> [FileStationItem] {
        try await fileStation.search(
            criteria: criteria,
            resultOptions: resultOptions,
            progress: progress
        )
    }

    func fileStationFavorites() async throws -> [FileStationFavorite] {
        try await fileStation.favorites()
    }

    func fileStationFavorites(
        status: FileStationFavoriteStatus,
        offset: Int,
        limit: Int
    ) async throws -> FileStationPage<FileStationFavorite> {
        try await fileStation.favorites(status: status, offset: offset, limit: limit)
    }

    func addFileStationFavorite(path: String, name: String) async throws {
        try await fileStation.addFavorite(path: path, name: name)
    }

    func removeFileStationFavorite(path: String) async throws {
        try await fileStation.removeFavorite(path: path)
    }

    func editFileStationFavorite(path: String, name: String) async throws {
        try await fileStation.editFavorite(path: path, name: name)
    }

    func replaceFileStationFavorites(_ favorites: [FileStationFavorite]) async throws {
        try await fileStation.replaceFavorites(favorites)
    }

    func clearBrokenFileStationFavorites() async throws {
        try await fileStation.clearBrokenFavorites()
    }

    func compress(paths: [String], to destinationPath: String) async throws {
        try await fileStation.compress(paths: paths, to: destinationPath)
    }

    func compress(
        paths: [String],
        to destinationPath: String,
        progress: (FileOperationProgress) -> Void
    ) async throws {
        try await fileStation.compress(
            paths: paths,
            to: destinationPath,
            progress: progress
        )
    }

    func compress(
        paths: [String],
        to destinationPath: String,
        options: FileStationCompressionOptions,
        progress: (FileOperationProgress) -> Void
    ) async throws {
        try await fileStation.compress(
            paths: paths,
            to: destinationPath,
            options: options,
            progress: progress
        )
    }

    func extract(archivePath: String, to destinationFolder: String) async throws {
        try await fileStation.extract(archivePath: archivePath, to: destinationFolder)
    }

    func extract(
        archivePath: String,
        to destinationFolder: String,
        progress: (FileOperationProgress) -> Void
    ) async throws {
        try await fileStation.extract(
            archivePath: archivePath,
            to: destinationFolder,
            progress: progress
        )
    }

    func extract(
        archivePath: String,
        to destinationFolder: String,
        options: FileStationExtractionOptions,
        progress: (FileOperationProgress) -> Void
    ) async throws {
        try await fileStation.extract(
            archivePath: archivePath,
            to: destinationFolder,
            options: options,
            progress: progress
        )
    }

    func archiveItems(
        archivePath: String,
        options: FileStationArchiveListOptions
    ) async throws -> FileStationPage<FileStationArchiveItem> {
        try await fileStation.archiveItems(archivePath: archivePath, options: options)
    }

    func checkFileStationWritePermission(
        in folderPath: String,
        filename: String,
        conflictPolicy: FileConflictPolicy,
        createOnly: Bool
    ) async throws {
        try await fileStation.checkWritePermission(
            in: folderPath,
            filename: filename,
            conflictPolicy: conflictPolicy,
            createOnly: createOnly
        )
    }

    func fileStationDirectorySize(
        paths: [String],
        progress: (FileOperationProgress) -> Void
    ) async throws -> FileStationDirectorySize {
        try await fileStation.directorySize(paths: paths, progress: progress)
    }

    func fileStationChecksum(
        path: String,
        progress: (FileOperationProgress) -> Void
    ) async throws -> String {
        try await fileStation.checksum(path: path, progress: progress)
    }

    func fileStationBackgroundTasks() async throws -> [FileStationBackgroundTask] {
        try await fileStation.backgroundTasks()
    }

    func fileStationBackgroundTasks(
        options: FileStationBackgroundTaskListOptions
    ) async throws -> FileStationPage<FileStationBackgroundTask> {
        try await fileStation.backgroundTasks(options: options)
    }

    func clearFinishedFileStationBackgroundTasks(taskIDs: [String]) async throws {
        try await fileStation.clearFinishedBackgroundTasks(taskIDs: taskIDs)
    }

    func stopFileStationOperation(kind: FileOperationKind, taskID: String) async throws {
        try await fileStation.stopOperation(kind: kind, taskID: taskID)
    }

    func createShareLink(
        path: String,
        password: String?,
        dateExpired: String?
    ) async throws -> String {
        try await fileStation.createShareLink(
            path: path,
            password: password,
            expirationDate: dateExpired
        )
    }

    func createShareLinks(_ creation: FileStationShareLinkCreation) async throws -> [SharingLink] {
        try await fileStation.createShareLinks(creation)
    }

    func shareLinkInformation(id: String) async throws -> SharingLink {
        try await fileStation.shareLinkInformation(id: id)
    }

    func listShareLinks() async throws -> [SharingLink] {
        try await fileStation.shareLinks()
    }

    func listShareLinks(
        options: FileStationSharingListOptions
    ) async throws -> FileStationPage<SharingLink> {
        try await fileStation.shareLinks(options: options)
    }

    func deleteShareLink(id: String) async throws {
        try await fileStation.deleteShareLink(id: id)
    }

    func deleteShareLinks(ids: [String]) async throws {
        try await fileStation.deleteShareLinks(ids: ids)
    }

    func editShareLinks(ids: [String], changes: FileStationShareLinkChanges) async throws {
        try await fileStation.editShareLinks(ids: ids, changes: changes)
    }

    func clearInvalidShareLinks() async throws {
        try await fileStation.clearInvalidShareLinks()
    }

    func storageInfo() async throws -> StorageInfo {
        try await storage.information()
    }

    func resourceUsage() async throws -> ResourceUsage {
        try await system.resourceUsage()
    }

    func listSharedFolders() async throws -> [SharedFolder] {
        try await shares.folders()
    }

    func createSharedFolder(
        name: String,
        volumePath: String,
        description: String
    ) async throws {
        try await shares.create(name: name, volumePath: volumePath, description: description)
    }

    func deleteSharedFolder(name: String) async throws {
        try await shares.delete(name: name)
    }

    func fileServiceEnabled(_ service: FileService) async throws -> Bool? {
        try await fileServiceSettings.isEnabled(service)
    }

    func setFileService(_ service: FileService, enabled: Bool) async throws {
        try await fileServiceSettings.set(service, enabled: enabled)
    }

    func packageCenterCapabilities() async throws -> PackageCenterCapabilities {
        packages.capabilities()
    }

    func listPackages() async throws -> [PackageInfo] {
        try await packages.installedPackages()
    }

    func officialPackageCatalog(forceRefresh: Bool) async throws -> [PackageUpdate] {
        try await packages.officialCatalog(forceRefresh: forceRefresh)
    }

    func availablePackageUpdates() async throws -> [String: PackageUpdate] {
        try await packages.availableUpdates()
    }

    func upgradePackage(_ update: PackageUpdate) async throws {
        try await packages.upgrade(update)
    }

    func upgradePackage(
        _ update: PackageUpdate,
        progress: (PackageOperationProgress) -> Void
    ) async throws {
        try await packages.upgrade(update, progress: progress)
    }

    func installPackage(
        _ update: PackageUpdate,
        progress: (PackageOperationProgress) -> Void
    ) async throws {
        try await packages.install(update, progress: progress)
    }

    func repairPackage(
        _ update: PackageUpdate,
        installsNewerVersion: Bool,
        progress: (PackageOperationProgress) -> Void
    ) async throws {
        try await packages.repair(
            update,
            installsNewerVersion: installsNewerVersion,
            progress: progress
        )
    }

    func installManualPackage(
        at fileURL: URL,
        progress: @escaping DSMTransferProgressHandler
    ) async throws -> String {
        try await packages.installManualPackage(at: fileURL, progress: progress)
    }

    func setPackageRunning(id: String, running: Bool) async throws {
        try await packages.setRunning(running, packageID: id)
    }

    func uninstallPackage(id: String) async throws {
        try await packages.uninstall(packageID: id)
    }

    func packageSettings() async throws -> PackageSettings {
        try await packages.settings()
    }

    func setPackageSettings(_ settings: PackageSettings) async throws {
        try await packages.setSettings(settings)
    }

    func packageSources() async throws -> [PackageSource] {
        try await packages.packageSources()
    }

    func addPackageSource(_ source: PackageSource) async throws {
        try await packages.addPackageSource(source)
    }

    func updatePackageSource(_ source: PackageSource, originalFeed: String) async throws {
        try await packages.updatePackageSource(source, originalFeed: originalFeed)
    }

    func deletePackageSources(feeds: [String]) async throws {
        try await packages.deletePackageSources(feeds: feeds)
    }

    func listUsers() async throws -> [DSMUser] {
        try await accounts.users()
    }

    func listGroups() async throws -> [DSMGroup] {
        try await accounts.groups()
    }

    func createUser(_ draft: DSMUserDraft) async throws {
        try await accounts.createUser(draft)
    }

    func setUser(_ name: String, disabled: Bool) async throws {
        try await accounts.setUser(name, disabled: disabled)
    }

    func deleteUser(_ name: String) async throws {
        try await accounts.deleteUser(name)
    }

    func createGroup(_ draft: DSMGroupDraft) async throws {
        try await accounts.createGroup(draft)
    }

    func deleteGroup(_ name: String) async throws {
        try await accounts.deleteGroup(name)
    }

    func listDownloadTasks() async throws -> [DownloadTask] {
        try await downloadStation.tasks()
    }

    func downloadStatistic() async throws -> DownloadStatistic {
        try await downloadStation.statistic()
    }

    func createDownload(uri: String, destination: String?) async throws {
        try await downloadStation.create(uri: uri, destination: destination)
    }

    func pauseDownloads(ids: Set<String>) async throws {
        try await downloadStation.pause(ids: ids)
    }

    func resumeDownloads(ids: Set<String>) async throws {
        try await downloadStation.resume(ids: ids)
    }

    func deleteDownloads(ids: Set<String>, forceComplete: Bool) async throws {
        try await downloadStation.delete(ids: ids, forceComplete: forceComplete)
    }

    func listUSBCopyTasks() async throws -> [USBCopyTask] {
        try await usbCopy.tasks()
    }

    func usbCopyTask(id: Int) async throws -> USBCopyTask {
        try await usbCopy.task(id: id)
    }

    func createUSBCopyTask(_ task: USBCopyTaskCreation) async throws -> Int {
        try await usbCopy.create(task)
    }

    func setUSBCopyTaskSettings(_ settings: USBCopyTaskSettings) async throws {
        try await usbCopy.setSettings(settings)
    }

    func usbCopyFilter(taskID: Int) async throws -> USBCopyFilter {
        try await usbCopy.filter(taskID: taskID)
    }

    func setUSBCopyFilter(_ filter: USBCopyFilter, taskID: Int) async throws {
        try await usbCopy.setFilter(filter, taskID: taskID)
    }

    func usbCopyTrigger(for task: USBCopyTask) async throws -> USBCopyTrigger {
        try await usbCopy.trigger(for: task)
    }

    func setUSBCopyTrigger(_ trigger: USBCopyTrigger, taskID: Int) async throws {
        _ = try await usbCopy.setTrigger(trigger, taskID: taskID)
    }

    func usbCopyGlobalSettings() async throws -> USBCopyGlobalSettings {
        try await usbCopy.globalSettings()
    }

    func setUSBCopyGlobalSettings(_ settings: USBCopyGlobalSettings) async throws {
        try await usbCopy.setGlobalSettings(settings)
    }

    func usbCopyLogs(
        offset: Int,
        limit: Int,
        filter: USBCopyLogFilter
    ) async throws -> USBCopyLogPage {
        try await usbCopy.logs(offset: offset, limit: limit, filter: filter)
    }

    func usbCopyAvailableShares() async throws -> [SharedFolder] {
        try await usbCopy.availableShares()
    }

    func usbCopyAvailableVolumePaths() async throws -> [String] {
        try await usbCopy.availableVolumePaths()
    }

    func runUSBCopyTask(id: Int) async throws {
        try await usbCopy.run(taskID: id)
    }

    func cancelUSBCopyTask(id: Int) async throws {
        try await usbCopy.cancel(taskID: id)
    }

    func enableUSBCopyTask(id: Int) async throws {
        try await usbCopy.enable(taskID: id)
    }

    func disableUSBCopyTask(id: Int) async throws {
        try await usbCopy.disable(taskID: id)
    }

    func deleteUSBCopyTask(id: Int) async throws {
        try await usbCopy.delete(taskID: id)
    }

    func listVirtualMachines() async throws -> [VirtualMachine] {
        try await virtualMachines.guests()
    }

    func performVirtualMachineAction(
        _ action: VirtualMachinePowerAction,
        guestID: String
    ) async throws {
        try await virtualMachines.perform(action, guestID: guestID)
    }

    func listContainers() async throws -> [ContainerItem] {
        try await containers.containers()
    }

    func performContainerAction(_ action: ContainerAction, name: String) async throws {
        try await containers.perform(action, name: name)
    }

    func containerLogs(name: String) async throws -> [ContainerLogEntry] {
        try await containers.logs(name: name)
    }

    func listSurveillanceCameras() async throws -> [SurveillanceCamera] {
        try await surveillance.cameras()
    }

    func setSurveillanceCameras(ids: Set<String>, enabled: Bool) async throws {
        try await surveillance.setEnabled(enabled, ids: ids)
    }

    func surveillanceSnapshot(cameraID: String) async throws -> Data {
        try await surveillance.snapshot(cameraID: cameraID)
    }

    func listSystemLogs() async throws -> [SystemLogEntry] {
        try await logsSecurity.logs()
    }

    func listBlockedAddresses() async throws -> [BlockedAddress] {
        try await logsSecurity.blockedAddresses()
    }

    func unblockAddress(_ address: String) async throws {
        try await logsSecurity.unblock(address)
    }

    func networkInfo() async throws -> NetworkInfo {
        try await network.information()
    }

    func logout() async throws {
        await authentication.logout()
    }
}
