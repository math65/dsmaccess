//
//  FileBrowserViewModel.swift
//  dsmaccess
//
//  Navigation, recherche et opérations File Station.
//

import Foundation
import Observation

@MainActor
@Observable
final class FileBrowserViewModel {
    struct Level: Equatable {
        let name: String
        let path: String?
        let writePermissionHint: Bool?

        init(name: String, path: String?, writePermissionHint: Bool? = nil) {
            self.name = name
            self.path = path
            self.writePermissionHint = writePermissionHint
        }
    }

    struct Clipboard {
        let items: [FileStationItem]
        let movesItems: Bool
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case name
        case modificationDate
        case size
        case kind

        var id: Self { self }

        var title: String {
            switch self {
            case .name: String(localized: "Nom")
            case .modificationDate: String(localized: "Date de modification")
            case .size: String(localized: "Taille")
            case .kind: String(localized: "Type")
            }
        }
    }

    private(set) var stack: [Level]
    private(set) var items: [FileStationItem] = []
    private(set) var favorites: [FileStationFavorite] = []
    private(set) var managedFavorites: [FileStationFavorite] = []
    private(set) var virtualFolders: [FileStationItem] = []
    private(set) var isLoading = false
    private(set) var isSearching = false
    private(set) var isWorking = false
    private(set) var isShowingSearchResults = false
    private(set) var searchQuery = ""
    private(set) var searchProgress: FileStationSearchProgress?
    private(set) var operationProgress: FileOperationProgress?
    private(set) var activeOperationLabel: String?
    private(set) var clipboard: Clipboard?
    private(set) var shareLinks: [SharingLink] = []
    private(set) var isLoadingShareLinks = false
    private(set) var shareLinkDetails: SharingLink?
    private(set) var isLoadingShareLinkDetails = false
    private(set) var transfers: [FileTransferRecord] = []
    private(set) var capabilities: FileStationCapabilities?
    private(set) var currentFolderIsWritable: Bool?
    private(set) var backgroundTasks: [FileStationBackgroundTask] = []
    private(set) var isLoadingBackgroundTasks = false
    private(set) var inspectorItem: FileStationItem?
    private(set) var inspectorDirectorySize: FileStationDirectorySize?
    private(set) var inspectorChecksum: String?
    private(set) var inspectorThumbnail: Data?
    private(set) var isLoadingInspector = false
    private(set) var isLoadingInspectorDetails = false
    private(set) var isCalculatingInspectorSize = false
    private(set) var isCalculatingInspectorChecksum = false
    private(set) var archiveItems: [FileStationArchiveItem] = []
    private(set) var isLoadingArchive = false
    private(set) var isLoadingManagedFavorites = false
    private(set) var isLoadingVirtualFolders = false

    var errorMessage: String?
    var shareLinksError: String?
    var shareLinkDetailsError: String?
    var favoritesError: String?
    var managedFavoritesError: String?
    var virtualFoldersError: String?
    var permissionMessage: String?
    var backgroundTasksError: String?
    var inspectorError: String?
    var inspectorDetailErrors: [String] = []
    var archiveError: String?
    var sortMode = SortMode.name
    var sortAscending = true

    private var directoryItems: [FileStationItem] = []
    private var activeDownloadCount = 0
    private let session: SessionStore
    private var loadGeneration = 0
    private var searchGeneration = 0
    private var shareLinksGeneration = 0
    private var shareLinkDetailsGeneration = 0
    private var shareLinksOptions = FileStationSharingListOptions()
    private var favoritesGeneration = 0
    private var managedFavoritesGeneration = 0
    private var virtualFoldersGeneration = 0
    private var managedFavoriteStatus = FileStationFavoriteStatus.all
    private var backgroundTasksGeneration = 0
    private var inspectorGeneration = 0
    private var archiveGeneration = 0
    private var advancedSearchCriteria: FileStationSearchCriteria?

    init(session: SessionStore) {
        self.session = session
        stack = [Level(name: String(localized: "Fichiers"), path: nil)]
    }

    var currentLevel: Level {
        stack.last ?? Level(name: String(localized: "Fichiers"), path: nil)
    }

    var title: String { currentLevel.name }
    var canGoUp: Bool { stack.count > 1 }
    var canWrite: Bool { currentLevel.path != nil && currentFolderIsWritable != false }
    var canPaste: Bool { clipboard != nil && canWrite }
    var hasActiveTransfers: Bool {
        transfers.contains { $0.state == .queued || $0.state == .running }
    }
    var breadcrumb: String { stack.map(\.name).joined(separator: " ▸ ") }

    var canDownload: Bool { supports(.download) }
    // Compteur plutôt que booléen : les promesses de fichiers collées dans le
    // Finder peuvent déclencher plusieurs téléchargements simultanés.
    var isDownloading: Bool { activeDownloadCount > 0 }
    var canUpload: Bool { canWrite && supports(.upload) }
    var canCreateFolder: Bool { canWrite && supports(.createFolder) }
    var canRename: Bool { canWrite && supports(.rename) }
    var canCopyMove: Bool { canWrite && supports(.copyMove) }
    var canDelete: Bool { canWrite && supports(.delete) }
    var canCompress: Bool { canWrite && supports(.compress) }
    var canExtractArchives: Bool { canWrite && supports(.extract) }
    var canShare: Bool {
        canWrite
            && supports(.sharing)
            && capabilities?.information?.supportsSharing != false
    }

    var availableVirtualFolderTypes: [FileStationVirtualFolderType] {
        guard supports(.virtualFolders) else { return [] }
        guard let information = capabilities?.information else {
            return FileStationVirtualFolderType.allCases
        }
        return FileStationVirtualFolderType.allCases.filter {
            information.supportedVirtualProtocols.contains($0.rawValue)
        }
    }

    func supports(_ feature: FileStationFeature) -> Bool {
        capabilities?.supports(feature) == true
    }

    var sortedItems: [FileStationItem] {
        items.sorted { left, right in
            if left.isdir != right.isdir {
                return left.isdir && !right.isdir
            }
            let result: ComparisonResult
            switch sortMode {
            case .name:
                result = left.name.localizedStandardCompare(right.name)
            case .modificationDate:
                result = compare(left.additional?.time?.mtime, right.additional?.time?.mtime)
            case .size:
                result = compare(left.additional?.size, right.additional?.size)
            case .kind:
                let leftKind = left.additional?.type ?? left.name.pathExtension
                let rightKind = right.additional?.type ?? right.name.pathExtension
                result = leftKind.localizedStandardCompare(rightKind)
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    func loadCurrent() async {
        loadGeneration += 1
        let generation = loadGeneration
        let level = currentLevel
        isLoading = true
        errorMessage = nil
        permissionMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            if capabilities == nil {
                capabilities = try await session.withClient { try await $0.fileStationCapabilities() }
            }
            guard supports(.browsing) else {
                throw DSMError.unsupportedAPI(FileStationFeature.browsing.requiredAPI.name)
            }
            let result = try await session.withClient { client in
                if let path = level.path {
                    return try await client.list(folderPath: path)
                } else {
                    return try await client.listShares()
                }
            }
            guard generation == loadGeneration, currentLevel == level else { return }
            directoryItems = result
            items = result
            isShowingSearchResults = false
            await loadWritePermission(for: level, generation: generation)
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = errorMessage(for: error)
        }
    }

    func loadFavorites() async {
        favoritesGeneration += 1
        let generation = favoritesGeneration
        favoritesError = nil
        guard supports(.favorites) else {
            favorites = []
            return
        }
        do {
            let result = try await session.withClient { try await $0.fileStationFavorites() }
            guard generation == favoritesGeneration else { return }
            favorites = result
        } catch {
            guard generation == favoritesGeneration, !DSMError.isCancellation(error) else { return }
            favorites = []
            favoritesError = errorMessage(for: error)
        }
    }

    func loadManagedFavorites(status: FileStationFavoriteStatus) async {
        managedFavoriteStatus = status
        managedFavoritesGeneration += 1
        let generation = managedFavoritesGeneration
        isLoadingManagedFavorites = true
        managedFavoritesError = nil
        defer {
            if generation == managedFavoritesGeneration {
                isLoadingManagedFavorites = false
            }
        }
        guard supports(.favorites) else {
            managedFavorites = []
            managedFavoritesError = unavailableMessage(for: .favorites)
            return
        }
        do {
            let result = try await session.withClient {
                try await $0.fileStationFavorites(status: status, offset: 0, limit: 0)
            }
            guard generation == managedFavoritesGeneration,
                  status == managedFavoriteStatus else { return }
            managedFavorites = result.elements
        } catch {
            guard generation == managedFavoritesGeneration,
                  !DSMError.isCancellation(error) else { return }
            managedFavorites = []
            managedFavoritesError = errorMessage(for: error)
        }
    }

    func loadVirtualFolders(
        type: FileStationVirtualFolderType,
        options: FileStationListOptions = FileStationListOptions()
    ) async {
        virtualFoldersGeneration += 1
        let generation = virtualFoldersGeneration
        isLoadingVirtualFolders = true
        virtualFoldersError = nil
        defer {
            if generation == virtualFoldersGeneration {
                isLoadingVirtualFolders = false
            }
        }
        guard availableVirtualFolderTypes.contains(type) else {
            virtualFolders = []
            virtualFoldersError = String(
                localized: "Ce NAS ne prend pas en charge les dossiers virtuels \(type.rawValue.uppercased())."
            )
            return
        }
        do {
            let result = try await session.withClient {
                try await $0.virtualFolders(type: type, options: options)
            }
            guard generation == virtualFoldersGeneration else { return }
            virtualFolders = result.elements
        } catch {
            guard generation == virtualFoldersGeneration,
                  !DSMError.isCancellation(error) else { return }
            virtualFolders = []
            virtualFoldersError = errorMessage(for: error)
        }
    }

    func search(_ query: String) async {
        let pattern = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration
        advancedSearchCriteria = nil
        searchProgress = nil
        searchQuery = pattern
        guard !pattern.isEmpty else {
            isSearching = false
            isShowingSearchResults = false
            errorMessage = nil
            items = directoryItems
            return
        }

        if currentLevel.path == nil {
            items = directoryItems.filter {
                $0.name.localizedStandardContains(pattern)
            }
            isShowingSearchResults = true
            return
        }

        guard let path = currentLevel.path else { return }
        guard supports(.search) else {
            items = directoryItems.filter {
                $0.name.localizedStandardContains(pattern)
            }
            isShowingSearchResults = true
            return
        }
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }
        errorMessage = nil
        do {
            let result = try await session.withClient {
                try await $0.searchFiles(in: path, matching: pattern)
            }
            guard generation == searchGeneration, searchQuery == pattern else { return }
            items = result
            isShowingSearchResults = true
        } catch {
            guard generation == searchGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = errorMessage(for: error)
        }
    }

    func search(_ criteria: FileStationSearchCriteria) async {
        guard let path = currentLevel.path, supports(.search) else { return }
        searchGeneration += 1
        let generation = searchGeneration
        var scopedCriteria = criteria
        scopedCriteria.folderPaths = [path]
        advancedSearchCriteria = scopedCriteria
        searchQuery = scopedCriteria.pattern?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        searchProgress = nil
        isSearching = true
        isShowingSearchResults = true
        errorMessage = nil
        defer { if generation == searchGeneration { isSearching = false } }
        do {
            let result = try await session.withClient {
                try await $0.searchFiles(
                    criteria: scopedCriteria,
                    resultOptions: FileStationSearchResultOptions(),
                    progress: { [weak self] progress in
                        guard self?.searchGeneration == generation else { return }
                        self?.searchProgress = progress
                    }
                )
            }
            guard generation == searchGeneration,
                  advancedSearchCriteria == scopedCriteria else { return }
            items = result
            searchProgress = nil
        } catch {
            guard generation == searchGeneration,
                  !DSMError.isCancellation(error) else { return }
            searchProgress = nil
            errorMessage = errorMessage(for: error)
        }
    }

    func reloadCurrentSearch(simpleQuery: String) async {
        let criteria = advancedSearchCriteria
        await loadCurrent()
        if let criteria {
            await search(criteria)
        } else if !simpleQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await search(simpleQuery)
        }
    }

    func open(_ item: FileStationItem) async {
        guard item.isdir else { return }
        advancedSearchCriteria = nil
        searchProgress = nil
        searchQuery = ""
        stack.append(
            Level(
                name: item.name,
                path: item.path,
                writePermissionHint: writePermissionHint(for: item)
            )
        )
        currentFolderIsWritable = stack.last?.writePermissionHint
        await loadCurrent()
    }

    func openFavorite(_ favorite: FileStationFavorite) async {
        guard favorite.isAvailable else { return }
        advancedSearchCriteria = nil
        searchProgress = nil
        searchQuery = ""
        stack = [
            Level(name: String(localized: "Fichiers"), path: nil),
            Level(
                name: favorite.name,
                path: favorite.path,
                writePermissionHint: writePermissionHint(for: favorite.additional)
            ),
        ]
        currentFolderIsWritable = stack.last?.writePermissionHint
        await loadCurrent()
    }

    func openVirtualFolder(_ folder: FileStationItem) async {
        guard folder.isdir else { return }
        advancedSearchCriteria = nil
        searchProgress = nil
        searchQuery = ""
        stack = [
            Level(name: String(localized: "Fichiers"), path: nil),
            Level(
                name: folder.name,
                path: folder.path,
                writePermissionHint: writePermissionHint(for: folder)
            ),
        ]
        currentFolderIsWritable = stack.last?.writePermissionHint
        await loadCurrent()
    }

    func goUp() async {
        guard canGoUp else { return }
        advancedSearchCriteria = nil
        searchProgress = nil
        searchQuery = ""
        stack.removeLast()
        currentFolderIsWritable = currentLevel.writePermissionHint
        await loadCurrent()
    }

    func suggestedFilename(for item: FileStationItem) -> String {
        item.promisedFileName
    }

    func download(_ item: FileStationItem, to destination: URL) async -> DSMOperationOutcome {
        guard canDownload else { return unavailableOutcome(for: .download) }
        defer { destination.stopAccessingSecurityScopedResource() }
        return await performSingleDownload(item, to: destination)
    }

    /// Téléchargement déclenché par une promesse de fichier collée dans le Finder.
    /// Aucun scope de sécurité à gérer : l'URL de destination est couverte par le
    /// sandbox du récepteur de la promesse.
    func downloadForFinderPromise(
        _ item: FileStationItem,
        to destination: URL
    ) async -> DSMOperationOutcome {
        guard canDownload else { return unavailableOutcome(for: .download) }
        return await performSingleDownload(item, to: destination)
    }

    private func performSingleDownload(
        _ item: FileStationItem,
        to destination: URL
    ) async -> DSMOperationOutcome {
        let transferID = addTransfer(
            direction: .download,
            name: item.name,
            source: item.path,
            destination: destination.path
        )
        activeDownloadCount += 1
        defer { activeDownloadCount -= 1 }
        updateTransfer(id: transferID, state: .running)
        do {
            try await session.withClient {
                try await $0.downloadFile(
                    path: item.path,
                    to: destination,
                    progress: { [weak self] progress in
                        self?.updateTransfer(id: transferID, progress: progress)
                    }
                )
            }
            updateTransfer(id: transferID, state: .completed)
            return .success(String(localized: "Téléchargement terminé : \(item.name)"))
        } catch {
            if DSMError.isCancellation(error) {
                updateTransfer(id: transferID, state: .cancelled)
                return .cancelled
            }
            let message = errorMessage(for: error)
            updateTransfer(id: transferID, state: .failed(message))
            return .failure(String(localized: "Échec du téléchargement : \(message)"))
        }
    }

    func download(_ selectedItems: [FileStationItem], to directory: URL) async -> DSMOperationOutcome {
        guard canDownload else { return unavailableOutcome(for: .download) }
        defer { directory.stopAccessingSecurityScopedResource() }
        activeDownloadCount += 1
        defer { activeDownloadCount -= 1 }
        var completed = 0
        var firstError: String?
        let queuedTransfers = selectedItems.map { item in
            let destination = directory.appendingPathComponent(suggestedFilename(for: item))
            return (
                item,
                destination,
                addTransfer(
                    direction: .download,
                    name: item.name,
                    source: item.path,
                    destination: destination.path
                )
            )
        }
        for (index, transfer) in queuedTransfers.enumerated() {
            let (item, destination, transferID) = transfer
            do {
                try Task.checkCancellation()
                updateTransfer(id: transferID, state: .running)
                try await session.withClient {
                    try await $0.downloadFile(
                        path: item.path,
                        to: destination,
                        progress: { [weak self] progress in
                            self?.updateTransfer(id: transferID, progress: progress)
                        }
                    )
                }
                updateTransfer(id: transferID, state: .completed)
                completed += 1
            } catch where DSMError.isCancellation(error) {
                updateTransfer(id: transferID, state: .cancelled)
                for remaining in queuedTransfers.dropFirst(index + 1) {
                    updateTransfer(id: remaining.2, state: .cancelled)
                }
                return .cancelled
            } catch {
                let message = errorMessage(for: error)
                updateTransfer(id: transferID, state: .failed(message))
                if firstError == nil { firstError = message }
            }
        }
        if completed == selectedItems.count {
            return .success(String(localized: "\(completed) éléments téléchargés"))
        }
        return .failure(
            String(localized: "\(completed) téléchargés, \(selectedItems.count - completed) en échec. \(firstError ?? "")")
        )
    }

    func downloadAsArchive(
        _ selectedItems: [FileStationItem],
        to destination: URL
    ) async -> DSMOperationOutcome {
        guard canDownload else { return unavailableOutcome(for: .download) }
        guard selectedItems.count > 1 else {
            return .failure(String(localized: "Sélectionnez au moins deux éléments à archiver."))
        }
        defer { destination.stopAccessingSecurityScopedResource() }
        let transferID = addTransfer(
            direction: .download,
            name: destination.lastPathComponent,
            source: String(localized: "\(selectedItems.count) éléments File Station"),
            destination: destination.path
        )
        activeDownloadCount += 1
        defer { activeDownloadCount -= 1 }
        updateTransfer(id: transferID, state: .running)
        do {
            try await session.withClient {
                try await $0.downloadFiles(
                    paths: selectedItems.map(\.path),
                    to: destination,
                    progress: { [weak self] progress in
                        self?.updateTransfer(id: transferID, progress: progress)
                    }
                )
            }
            updateTransfer(id: transferID, state: .completed)
            return .success(
                String(localized: "Archive téléchargée : \(destination.lastPathComponent)")
            )
        } catch {
            if DSMError.isCancellation(error) {
                updateTransfer(id: transferID, state: .cancelled)
                return .cancelled
            }
            let message = errorMessage(for: error)
            updateTransfer(id: transferID, state: .failed(message))
            return .failure(String(localized: "Échec du téléchargement de l’archive : \(message)"))
        }
    }

    func createFolder(named name: String) async -> DSMOperationOutcome {
        guard canCreateFolder else { return unavailableOutcome(for: .createFolder) }
        guard let parent = currentLevel.path else {
            return .failure(String(localized: "Impossible de créer le dossier ici."))
        }
        return await performAndReload {
            try await self.session.withClient { try await $0.createFolder(in: parent, name: name) }
            return String(localized: "Dossier créé : \(name)")
        }
    }

    func rename(_ item: FileStationItem, to name: String) async -> DSMOperationOutcome {
        guard canRename else { return unavailableOutcome(for: .rename) }
        return await performAndReload {
            try await self.session.withClient { try await $0.rename(path: item.path, to: name) }
            return String(localized: "Renommé en : \(name)")
        }
    }

    func delete(_ selectedItems: [FileStationItem]) async -> DSMOperationOutcome {
        guard canDelete else { return unavailableOutcome(for: .delete) }
        return await performProgressOperation(label: String(localized: "Suppression")) { progress in
            try await self.session.withClient {
                try await $0.delete(paths: selectedItems.map(\.path), progress: progress)
            }
            return selectedItems.count == 1
                ? String(localized: "Supprimé : \(selectedItems[0].name)")
                : String(localized: "\(selectedItems.count) éléments supprimés")
        }
    }

    func upload(
        urls: [URL],
        options: FileStationUploadOptions = FileStationUploadOptions(conflictPolicy: .skip)
    ) async -> DSMOperationOutcome {
        // Les scopes de sécurité ont été ouverts par la vue sur les URL racines ;
        // les fichiers énumérés dans un dossier sont couverts par le scope de leur racine.
        defer {
            for url in urls { url.stopAccessingSecurityScopedResource() }
        }
        guard canUpload else { return unavailableOutcome(for: .upload) }
        guard let parent = currentLevel.path else {
            return .failure(String(localized: "Impossible d’envoyer ici."))
        }
        isWorking = true
        defer { isWorking = false }
        let plan = await FinderUploadPlan.make(from: urls)
        if !plan.folders.isEmpty {
            do {
                try Task.checkCancellation()
                // force_parent rend la création idempotente : un dossier déjà
                // présent sur le NAS est fusionné, pas signalé en erreur.
                _ = try await session.withClient {
                    try await $0.createFolders(
                        plan.folderCreations(under: parent),
                        forceParentFolders: true
                    )
                }
            } catch where DSMError.isCancellation(error) {
                return .cancelled
            } catch {
                return .failure(
                    String(localized: "Impossible de créer les dossiers : \(errorMessage(for: error))")
                )
            }
        }
        var sent = 0
        var firstFailure: String?
        let query = searchQuery
        let criteria = advancedSearchCriteria
        let queuedTransfers = plan.files.map { file in
            (
                file,
                addTransfer(
                    direction: .upload,
                    name: file.source.lastPathComponent,
                    source: file.source.path,
                    destination: file.destinationFolder(under: parent)
                )
            )
        }
        for (index, transfer) in queuedTransfers.enumerated() {
            let (file, transferID) = transfer
            do {
                try Task.checkCancellation()
                updateTransfer(id: transferID, state: .running)
                try await session.withClient {
                    try await $0.upload(
                        fileURL: file.source,
                        to: file.destinationFolder(under: parent),
                        options: options,
                        progress: { [weak self] progress in
                            self?.updateTransfer(id: transferID, progress: progress)
                        }
                    )
                }
                updateTransfer(id: transferID, state: .completed)
                sent += 1
            } catch where DSMError.isCancellation(error) {
                updateTransfer(id: transferID, state: .cancelled)
                for remaining in queuedTransfers.dropFirst(index + 1) {
                    updateTransfer(id: remaining.1, state: .cancelled)
                }
                return .cancelled
            } catch {
                let message = errorMessage(for: error)
                updateTransfer(id: transferID, state: .failed(message))
                if firstFailure == nil { firstFailure = message }
            }
        }
        await loadCurrent()
        if let criteria {
            await search(criteria)
        } else if !query.isEmpty {
            await search(query)
        }
        let failed = plan.files.count - sent
        if failed > 0 {
            return .failure(
                String(localized: "\(sent) envoyés, \(failed) en échec : \(firstFailure ?? "")")
            )
        }
        if plan.unreadableItems > 0 {
            return .failure(
                String(localized: "Envoi incomplet : certains éléments n’ont pas pu être lus sur le Mac.")
            )
        }
        if plan.folders.isEmpty {
            let message = sent == 1
                ? String(localized: "Fichier envoyé : \(plan.files[0].source.lastPathComponent)")
                : String(localized: "\(sent) fichiers envoyés")
            return .success(message)
        }
        if urls.count == 1 {
            return .success(String(localized: "Dossier envoyé : \(urls[0].lastPathComponent)"))
        }
        return .success(String(localized: "\(urls.count) éléments envoyés"))
    }

    func clearFinishedTransfers() {
        transfers.removeAll { transfer in
            switch transfer.state {
            case .queued, .running:
                false
            case .completed, .cancelled, .failed:
                true
            }
        }
    }

    func loadBackgroundTasks() async {
        backgroundTasksGeneration += 1
        let generation = backgroundTasksGeneration
        guard supports(.backgroundTasks) else {
            backgroundTasks = []
            backgroundTasksError = String(localized: "Les tâches File Station ne sont pas disponibles sur ce NAS.")
            return
        }
        isLoadingBackgroundTasks = true
        backgroundTasksError = nil
        defer {
            if generation == backgroundTasksGeneration {
                isLoadingBackgroundTasks = false
            }
        }
        do {
            let result = try await session.withClient {
                try await $0.fileStationBackgroundTasks()
            }
            guard generation == backgroundTasksGeneration else { return }
            backgroundTasks = result
        } catch {
            guard generation == backgroundTasksGeneration,
                  !DSMError.isCancellation(error) else { return }
            backgroundTasksError = errorMessage(for: error)
        }
    }

    func stopBackgroundTask(_ task: FileStationBackgroundTask) async -> DSMOperationOutcome {
        guard let kind = FileOperationKind(rawValue: task.api) else {
            return .failure(String(localized: "Ce type de tâche ne peut pas être arrêté depuis l’application."))
        }
        do {
            try await session.withClient {
                try await $0.stopFileStationOperation(kind: kind, taskID: task.taskID)
            }
            await loadBackgroundTasks()
            return .success(String(localized: "Tâche File Station arrêtée"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec de l’arrêt de la tâche : \(errorMessage(for: error))")
            )
        }
    }

    func clearFinishedBackgroundTasks() async -> DSMOperationOutcome {
        do {
            let taskIDs = backgroundTasks.filter(\.finished).map(\.taskID)
            try await session.withClient {
                try await $0.clearFinishedFileStationBackgroundTasks(taskIDs: taskIDs)
            }
            await loadBackgroundTasks()
            return .success(String(localized: "Tâches File Station terminées effacées"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec de l’effacement des tâches : \(errorMessage(for: error))")
            )
        }
    }

    func loadInspector(for selectedItem: FileStationItem) async {
        inspectorGeneration += 1
        let generation = inspectorGeneration
        inspectorItem = nil
        inspectorDirectorySize = nil
        inspectorChecksum = nil
        inspectorThumbnail = nil
        inspectorError = nil
        inspectorDetailErrors = []
        isLoadingInspector = true
        isLoadingInspectorDetails = false

        do {
            let information = try await session.withClient {
                try await $0.fileInformation(paths: [selectedItem.path])
            }
            guard generation == inspectorGeneration else { return }
            guard let item = information.first else { throw DSMError.invalidResponse }
            inspectorItem = item
            isLoadingInspector = false
            await loadInspectorDetails(for: item, generation: generation)
        } catch {
            guard generation == inspectorGeneration,
                  !DSMError.isCancellation(error) else { return }
            isLoadingInspector = false
            inspectorError = errorMessage(for: error)
        }
    }

    func clearInspector() {
        inspectorGeneration += 1
        inspectorItem = nil
        inspectorDirectorySize = nil
        inspectorChecksum = nil
        inspectorThumbnail = nil
        inspectorError = nil
        inspectorDetailErrors = []
        isLoadingInspector = false
        isLoadingInspectorDetails = false
        isCalculatingInspectorSize = false
        isCalculatingInspectorChecksum = false
    }

    func calculateInspectorDirectorySize() async {
        guard let item = inspectorItem, item.isdir, supports(.directorySize) else { return }
        let generation = inspectorGeneration
        isCalculatingInspectorSize = true
        defer {
            if generation == inspectorGeneration {
                isCalculatingInspectorSize = false
            }
        }
        do {
            let size = try await session.withClient {
                try await $0.fileStationDirectorySize(paths: [item.path], progress: { _ in })
            }
            guard generation == inspectorGeneration else { return }
            inspectorDirectorySize = size
        } catch {
            guard generation == inspectorGeneration,
                  !DSMError.isCancellation(error) else { return }
            appendInspectorDetailError(
                String(localized: "Taille du dossier indisponible : \(errorMessage(for: error))")
            )
        }
    }

    func calculateInspectorChecksum() async {
        guard let item = inspectorItem, !item.isdir, supports(.checksum) else { return }
        let generation = inspectorGeneration
        isCalculatingInspectorChecksum = true
        defer {
            if generation == inspectorGeneration {
                isCalculatingInspectorChecksum = false
            }
        }
        do {
            let checksum = try await session.withClient {
                try await $0.fileStationChecksum(path: item.path, progress: { _ in })
            }
            guard generation == inspectorGeneration else { return }
            inspectorChecksum = checksum
        } catch {
            guard generation == inspectorGeneration,
                  !DSMError.isCancellation(error) else { return }
            appendInspectorDetailError(
                String(localized: "Somme MD5 indisponible : \(errorMessage(for: error))")
            )
        }
    }

    func loadArchive(
        _ item: FileStationItem,
        options: FileStationArchiveListOptions
    ) async {
        archiveGeneration += 1
        let generation = archiveGeneration
        isLoadingArchive = true
        archiveError = nil
        defer {
            if generation == archiveGeneration {
                isLoadingArchive = false
            }
        }
        do {
            let page = try await session.withClient {
                try await $0.archiveItems(archivePath: item.path, options: options)
            }
            guard generation == archiveGeneration else { return }
            archiveItems = page.elements
        } catch {
            guard generation == archiveGeneration,
                  !DSMError.isCancellation(error) else { return }
            archiveItems = []
            archiveError = errorMessage(for: error)
        }
    }

    func clearArchive() {
        archiveGeneration += 1
        archiveItems = []
        archiveError = nil
        isLoadingArchive = false
    }

    func copy(_ selectedItems: [FileStationItem]) -> String {
        clipboard = Clipboard(items: selectedItems, movesItems: false)
        return selectedItems.count == 1
            ? String(localized: "Copié : \(selectedItems[0].name)")
            : String(localized: "\(selectedItems.count) éléments copiés")
    }

    func cut(_ selectedItems: [FileStationItem]) -> String {
        clipboard = Clipboard(items: selectedItems, movesItems: true)
        return selectedItems.count == 1
            ? String(localized: "Coupé : \(selectedItems[0].name). Ouvrez la destination puis Coller pour déplacer.")
            : String(localized: "\(selectedItems.count) éléments coupés. Ouvrez la destination puis Coller pour déplacer.")
    }

    func paste(conflictPolicy: FileConflictPolicy = .skip) async -> DSMOperationOutcome {
        guard canCopyMove else { return unavailableOutcome(for: .copyMove) }
        guard let clipboard else { return .failure(String(localized: "Rien à coller.")) }
        guard let destination = currentLevel.path else {
            return .failure(String(localized: "Impossible de coller ici."))
        }
        let label = clipboard.movesItems
            ? String(localized: "Déplacement")
            : String(localized: "Copie")
        return await performProgressOperation(label: label) { progress in
            try await self.session.withClient {
                try await $0.copyMove(
                    paths: clipboard.items.map(\.path),
                    to: destination,
                    remove: clipboard.movesItems,
                    conflictPolicy: conflictPolicy,
                    progress: progress
                )
            }
            if clipboard.movesItems { self.clipboard = nil }
            return clipboard.movesItems
                ? String(localized: "\(clipboard.items.count) éléments déplacés ici")
                : String(localized: "\(clipboard.items.count) éléments copiés ici")
        }
    }

    func compress(
        _ selectedItems: [FileStationItem],
        archiveName: String,
        options: FileStationCompressionOptions = FileStationCompressionOptions()
    ) async -> DSMOperationOutcome {
        guard canCompress else { return unavailableOutcome(for: .compress) }
        guard let folder = currentLevel.path else {
            return .failure(String(localized: "Impossible de créer une archive ici."))
        }
        let trimmed = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedExtension = options.format.rawValue
        let currentExtension = trimmed.pathExtension.lowercased()
        let basename = ["zip", "7z"].contains(currentExtension)
            ? (trimmed as NSString).deletingPathExtension
            : trimmed
        let filename = "\(basename).\(expectedExtension)"
        let destination = folder.appendingNASPathComponent(filename)
        return await performProgressOperation(label: String(localized: "Compression")) { progress in
            try await self.session.withClient {
                try await $0.compress(
                    paths: selectedItems.map(\.path),
                    to: destination,
                    options: options,
                    progress: progress
                )
            }
            return String(localized: "Archive créée : \(filename)")
        }
    }

    func extract(
        _ item: FileStationItem,
        options: FileStationExtractionOptions = FileStationExtractionOptions()
    ) async -> DSMOperationOutcome {
        guard canExtractArchives else { return unavailableOutcome(for: .extract) }
        guard let folder = currentLevel.path else {
            return .failure(String(localized: "Impossible d’extraire l’archive ici."))
        }
        return await performProgressOperation(label: String(localized: "Extraction")) { progress in
            try await self.session.withClient {
                try await $0.extract(
                    archivePath: item.path,
                    to: folder,
                    options: options,
                    progress: progress
                )
            }
            return String(localized: "Archive extraite : \(item.name)")
        }
    }

    func canExtract(_ item: FileStationItem) -> Bool {
        guard !item.isdir else { return false }
        let extensions = ["zip", "gz", "tar", "tgz", "tbz", "bz2", "rar", "7z", "iso"]
        return extensions.contains(item.name.pathExtension.lowercased())
    }

    func isFavorite(path: String) -> Bool {
        favorites.contains { $0.path == path }
    }

    func toggleCurrentFavorite() async -> DSMOperationOutcome {
        guard supports(.favorites) else { return unavailableOutcome(for: .favorites) }
        guard let path = currentLevel.path else {
            return .failure(String(localized: "Impossible d’ajouter ce dossier aux favoris."))
        }
        do {
            if isFavorite(path: path) {
                try await session.withClient { try await $0.removeFileStationFavorite(path: path) }
                await loadFavorites()
                return .success(String(localized: "Favori supprimé : \(currentLevel.name)"))
            }
            try await session.withClient {
                try await $0.addFileStationFavorite(path: path, name: currentLevel.name)
            }
            await loadFavorites()
            return .success(String(localized: "Favori ajouté : \(currentLevel.name)"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec de la modification du favori : \(errorMessage(for: error))")
            )
        }
    }

    func renameFavorite(
        _ favorite: FileStationFavorite,
        to proposedName: String
    ) async -> DSMOperationOutcome {
        guard supports(.favorites) else { return unavailableOutcome(for: .favorites) }
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return .failure(String(localized: "Saisissez un nom pour le favori."))
        }
        do {
            try await session.withClient {
                try await $0.editFileStationFavorite(path: favorite.path, name: name)
            }
            await reloadFavoriteLists()
            return .success(String(localized: "Favori renommé : \(name)"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec du renommage du favori : \(errorMessage(for: error))")
            )
        }
    }

    func removeFavorite(_ favorite: FileStationFavorite) async -> DSMOperationOutcome {
        guard supports(.favorites) else { return unavailableOutcome(for: .favorites) }
        do {
            try await session.withClient {
                try await $0.removeFileStationFavorite(path: favorite.path)
            }
            await reloadFavoriteLists()
            return .success(String(localized: "Favori supprimé : \(favorite.name)"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec de la suppression du favori : \(errorMessage(for: error))")
            )
        }
    }

    func clearBrokenFavorites() async -> DSMOperationOutcome {
        guard supports(.favorites) else { return unavailableOutcome(for: .favorites) }
        do {
            try await session.withClient { try await $0.clearBrokenFileStationFavorites() }
            await reloadFavoriteLists()
            return .success(String(localized: "Favoris indisponibles effacés"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec de l’effacement des favoris indisponibles : \(errorMessage(for: error))")
            )
        }
    }

    func moveFavorite(_ favorite: FileStationFavorite, by offset: Int) async -> DSMOperationOutcome {
        guard supports(.favorites) else { return unavailableOutcome(for: .favorites) }
        guard managedFavoriteStatus == .all else {
            return .failure(
                String(localized: "Affichez tous les favoris pour modifier leur ordre.")
            )
        }
        guard let sourceIndex = managedFavorites.firstIndex(where: { $0.id == favorite.id }) else {
            return .failure(String(localized: "Ce favori n’est plus disponible."))
        }
        let destinationIndex = sourceIndex + offset
        guard managedFavorites.indices.contains(destinationIndex) else { return .cancelled }
        var reordered = managedFavorites
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: destinationIndex)
        do {
            try await session.withClient {
                try await $0.replaceFileStationFavorites(reordered)
            }
            await reloadFavoriteLists()
            return .success(String(localized: "Ordre des favoris modifié"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec du classement des favoris : \(errorMessage(for: error))")
            )
        }
    }

    private func reloadFavoriteLists() async {
        let status = managedFavoriteStatus
        await loadFavorites()
        await loadManagedFavorites(status: status)
    }

    enum ShareOutcome {
        case link(String)
        case failure(String)
        case cancelled
    }

    func createShareLink(
        for item: FileStationItem,
        password: String?,
        expirationDate: String?,
        availableDate: String?
    ) async -> ShareOutcome {
        guard canShare else {
            return .failure(unavailableMessage(for: .sharing))
        }
        do {
            let links = try await session.withClient {
                try await $0.createShareLinks(
                    FileStationShareLinkCreation(
                        paths: [item.path],
                        password: password,
                        expirationDate: expirationDate,
                        availableDate: availableDate
                    )
                )
            }
            guard let url = links.first?.url else { throw DSMError.invalidResponse }
            return .link(url)
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "Échec de la création du lien : \(errorMessage(for: error))"))
        }
    }

    func loadShareLinks(
        options: FileStationSharingListOptions = FileStationSharingListOptions()
    ) async {
        shareLinksOptions = options
        shareLinksGeneration += 1
        let generation = shareLinksGeneration
        isLoadingShareLinks = true
        shareLinksError = nil
        defer { if generation == shareLinksGeneration { isLoadingShareLinks = false } }
        do {
            let result = try await session.withClient {
                try await $0.listShareLinks(options: options).elements
            }
            guard generation == shareLinksGeneration else { return }
            shareLinks = result
        } catch {
            guard generation == shareLinksGeneration, !DSMError.isCancellation(error) else { return }
            shareLinksError = errorMessage(for: error)
        }
    }

    func loadShareLinkDetails(_ link: SharingLink) async {
        shareLinkDetailsGeneration += 1
        let generation = shareLinkDetailsGeneration
        isLoadingShareLinkDetails = true
        shareLinkDetails = nil
        shareLinkDetailsError = nil
        defer {
            if generation == shareLinkDetailsGeneration {
                isLoadingShareLinkDetails = false
            }
        }
        do {
            let details = try await session.withClient {
                try await $0.shareLinkInformation(id: link.id)
            }
            guard generation == shareLinkDetailsGeneration else { return }
            shareLinkDetails = details
        } catch {
            guard generation == shareLinkDetailsGeneration,
                  !DSMError.isCancellation(error) else { return }
            shareLinkDetailsError = errorMessage(for: error)
        }
    }

    func clearShareLinkDetails() {
        shareLinkDetailsGeneration += 1
        shareLinkDetails = nil
        shareLinkDetailsError = nil
        isLoadingShareLinkDetails = false
    }

    func editShareLink(
        _ link: SharingLink,
        changes: FileStationShareLinkChanges
    ) async -> DSMOperationOutcome {
        do {
            try await session.withClient {
                try await $0.editShareLinks(ids: [link.id], changes: changes)
            }
            await loadShareLinks(options: shareLinksOptions)
            return .success(String(localized: "Lien de partage modifié"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec de la modification du lien : \(errorMessage(for: error))")
            )
        }
    }

    func deleteShareLink(_ link: SharingLink) async -> DSMOperationOutcome {
        await deleteShareLinks([link])
    }

    func deleteShareLinks(_ links: [SharingLink]) async -> DSMOperationOutcome {
        guard !links.isEmpty else {
            return .failure(String(localized: "Aucun lien sélectionné."))
        }
        do {
            try await session.withClient {
                try await $0.deleteShareLinks(ids: links.map(\.id))
            }
            await loadShareLinks(options: shareLinksOptions)
            return links.count == 1
                ? .success(String(localized: "Lien supprimé"))
                : .success(String(localized: "\(links.count) liens supprimés"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec de la suppression du lien : \(errorMessage(for: error))")
            )
        }
    }

    func clearInvalidShareLinks() async -> DSMOperationOutcome {
        do {
            try await session.withClient { try await $0.clearInvalidShareLinks() }
            await loadShareLinks(options: shareLinksOptions)
            return .success(String(localized: "Liens invalides effacés"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(
                String(localized: "Échec de l’effacement des liens invalides : \(errorMessage(for: error))")
            )
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let count: String
        switch sortedItems.count {
        case 0: count = isShowingSearchResults ? String(localized: "Aucun résultat") : String(localized: "Dossier vide")
        case 1: count = String(localized: "1 élément")
        default: count = String(localized: "\(sortedItems.count) éléments")
        }
        let base = String(localized: "\(title), \(count)")
        guard let permissionMessage else { return base }
        return String(localized: "\(base). \(permissionMessage)")
    }

    private func performAndReload(
        _ operation: () async throws -> String
    ) async -> DSMOperationOutcome {
        isWorking = true
        defer { isWorking = false }
        do {
            let message = try await operation()
            let query = searchQuery
            let criteria = advancedSearchCriteria
            await loadCurrent()
            if let criteria {
                await search(criteria)
            } else if !query.isEmpty {
                await search(query)
            }
            return .success(message)
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "Échec de l’opération : \(errorMessage(for: error))"))
        }
    }

    private func performProgressOperation(
        label: String,
        _ operation: (_ progress: (FileOperationProgress) -> Void) async throws -> String
    ) async -> DSMOperationOutcome {
        isWorking = true
        activeOperationLabel = label
        operationProgress = nil
        defer {
            isWorking = false
            activeOperationLabel = nil
            operationProgress = nil
        }
        do {
            let message = try await operation { [weak self] progress in
                self?.operationProgress = progress
            }
            let query = searchQuery
            let criteria = advancedSearchCriteria
            await loadCurrent()
            if let criteria {
                await search(criteria)
            } else if !query.isEmpty {
                await search(query)
            }
            return .success(message)
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "Échec de l’opération : \(errorMessage(for: error))"))
        }
    }

    private func loadWritePermission(for level: Level, generation: Int) async {
        guard generation == loadGeneration, currentLevel == level else { return }
        currentFolderIsWritable = level.writePermissionHint
        guard let path = level.path else {
            currentFolderIsWritable = false
            return
        }
        guard supports(.writePermission) else { return }
        do {
            try await session.withClient {
                try await $0.checkFileStationWritePermission(
                    in: path,
                    filename: ".dsm-access-permission-\(UUID().uuidString)",
                    conflictPolicy: .skip,
                    createOnly: true
                )
            }
            guard generation == loadGeneration, currentLevel == level else { return }
            currentFolderIsWritable = true
        } catch {
            guard generation == loadGeneration,
                  currentLevel == level,
                  !DSMError.isCancellation(error) else { return }
            currentFolderIsWritable = false
            permissionMessage = String(
                localized: "Ce compte ne peut pas modifier ce dossier : \(errorMessage(for: error))"
            )
        }
    }

    private func loadInspectorDetails(for item: FileStationItem, generation: Int) async {
        isLoadingInspectorDetails = true
        defer {
            if generation == inspectorGeneration {
                isLoadingInspectorDetails = false
            }
        }

        if !item.isdir, item.supportsThumbnailPreview, supports(.thumbnails) {
            do {
                let data = try await session.withClient {
                    try await $0.fileThumbnail(
                        path: item.path,
                        size: .large,
                        rotation: .none
                    )
                }
                guard generation == inspectorGeneration else { return }
                inspectorThumbnail = data
            } catch {
                guard generation == inspectorGeneration,
                      !DSMError.isCancellation(error) else { return }
                appendInspectorDetailError(
                    String(localized: "Aperçu indisponible : \(errorMessage(for: error))")
                )
            }
        }
    }

    private func appendInspectorDetailError(_ message: String) {
        guard !inspectorDetailErrors.contains(message) else { return }
        inspectorDetailErrors.append(message)
    }

    private func writePermissionHint(for item: FileStationItem) -> Bool? {
        if item.additional?.volumeStatus?.isReadOnly == true
            || item.additional?.permission?.advancedRight?.disablesModify == true {
            return false
        }
        return item.additional?.permission?.acl?.write
    }

    private func writePermissionHint(for additional: FileStationItem.Additional?) -> Bool? {
        if additional?.volumeStatus?.isReadOnly == true
            || additional?.permission?.advancedRight?.disablesModify == true {
            return false
        }
        return additional?.permission?.acl?.write
    }

    private func unavailableOutcome(for feature: FileStationFeature) -> DSMOperationOutcome {
        .failure(unavailableMessage(for: feature))
    }

    private func unavailableMessage(for feature: FileStationFeature) -> String {
        if currentFolderIsWritable == false {
            return permissionMessage
                ?? String(localized: "Ce compte ne peut pas modifier ce dossier.")
        }
        return DSMError.unsupportedAPI(feature.requiredAPI.name).errorDescription
            ?? String(localized: "Cette opération n’est pas disponible sur ce NAS.")
    }

    private func addTransfer(
        direction: FileTransferDirection,
        name: String,
        source: String,
        destination: String
    ) -> UUID {
        let transfer = FileTransferRecord(
            direction: direction,
            name: name,
            source: source,
            destination: destination
        )
        transfers.insert(transfer, at: 0)
        return transfer.id
    }

    private func updateTransfer(
        id: UUID,
        progress: DSMTransferProgress? = nil,
        state: FileTransferState? = nil
    ) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        if let progress {
            transfers[index].progress = progress
        }
        if let state {
            transfers[index].state = state
            if state == .completed, transfers[index].progress == nil {
                transfers[index].progress = DSMTransferProgress(completedBytes: 1, totalBytes: 1)
            }
        }
    }

    private func errorMessage(for error: Error) -> String {
        (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }

    private func compare<Value: Comparable>(_ left: Value?, _ right: Value?) -> ComparisonResult {
        switch (left, right) {
        case let (left?, right?) where left < right: .orderedAscending
        case let (left?, right?) where left > right: .orderedDescending
        case (nil, .some): .orderedAscending
        case (.some, nil): .orderedDescending
        default: .orderedSame
        }
    }
}

private extension String {
    var pathExtension: String {
        (self as NSString).pathExtension
    }

    func appendingNASPathComponent(_ component: String) -> String {
        hasSuffix("/") ? self + component : self + "/" + component
    }
}
