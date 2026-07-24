//
//  FileBrowserView.swift
//  dsmaccess
//
//  Native Mac shell for File Station: toolbar, search, favourites, multi-selection,
//  file panels and accessible operation feedback.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileBrowserView: View {
    @State private var vm: FileBrowserViewModel
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var activeSheet: WriteSheet?
    @State private var pendingDeleteItems = [FileStationItem]()
    @State private var shareItem: FileStationItem?
    @State private var infoItem: FileStationItem?
    @State private var showingShareLinks = false
    @State private var showingFavorites = false
    @State private var showingVirtualFolders = false
    @State private var showingTransfers = false
    @State private var showingBackgroundTasks = false
    @State private var showingAdvancedSearch = false
    @State private var showingPasteOptions = false
    @State private var showingUploadOptions = false
    @State private var pendingUploadURLs = [URL]()
    @State private var extractionItem: FileStationItem?
    @State private var transferTask: Task<Void, Never>?
    @State private var advancedSearchTask: Task<Void, Never>?
    @State private var operationTask: Task<Void, Never>?
    @State private var tableFocusRequestID = 0
    @AccessibilityFocusState private var focusEmptyState: Bool

    private enum WriteSheet: Identifiable {
        case createFolder
        case rename(FileStationItem)
        case compress([FileStationItem])

        var id: String {
            switch self {
            case .createFolder: "create-folder"
            case .rename(let item): "rename-\(item.id)"
            case .compress(let items): "compress-\(items.map(\.id).joined(separator: "|"))"
            }
        }
    }

    init(session: SessionStore) {
        _vm = State(initialValue: FileBrowserViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let permissionMessage = vm.permissionMessage {
                Label(permissionMessage, systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .accessibilityLabel(permissionMessage)
            }
            if let label = vm.activeOperationLabel {
                FileOperationProgressBanner(
                    label: label,
                    progress: vm.operationProgress,
                    cancel: cancelOperation
                )
            }
            content
        }
            .navigationTitle(vm.title)
            .searchable(text: $searchText, prompt: "Rechercher dans ce dossier")
            .toolbar { fileToolbar }
            .focusedSceneValue(\.fileCommandActions, commandActions)
            .task {
                VoiceOver.announce(
                    String(localized: "Chargement des fichiers…"),
                    category: .progress,
                    priority: .low
                )
                await vm.loadCurrent()
                guard !Task.isCancelled else { return }
                await vm.loadFavorites()
                await VoiceOver.restoreFocusIfCapturedByToolbar(restoreInitialContentFocus)
                announceSummary()
            }
            .task(id: searchText) {
                // Au premier affichage cette tâche part avec un champ vide, avant la fin
                // du chargement : sans recherche à lancer ni à effacer, ne rien annoncer
                // (sinon VoiceOver entend « Dossier vide » puis le vrai contenu).
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty && !vm.isShowingSearchResults { return }
                do {
                    if !query.isEmpty {
                        try await Task.sleep(for: .milliseconds(300))
                    }
                    try Task.checkCancellation()
                    if !query.isEmpty {
                        VoiceOver.announce(
                            String(localized: "Recherche en cours…"),
                            category: .progress,
                            priority: .low
                        )
                    }
                    await vm.search(searchText)
                    try Task.checkCancellation()
                    selection.removeAll()
                    announceSummary()
                } catch is CancellationError {
                    return
                } catch {
                    VoiceOver.announce(
                        error.localizedDescription,
                        category: .error,
                        priority: .high
                    )
                }
            }
            .sheet(item: $activeSheet, content: writeSheet)
            .alert(
                deleteTitle,
                isPresented: Binding(
                    get: { !pendingDeleteItems.isEmpty },
                    set: { if !$0 { pendingDeleteItems.removeAll() } }
                )
            ) {
                Button("Supprimer", role: .destructive) {
                    let items = pendingDeleteItems
                    pendingDeleteItems.removeAll()
                    startOperation({ await vm.delete(items) }) {
                        selection.removeAll()
                    }
                }
                .help("Supprimer définitivement les éléments sélectionnés")
                Button("Annuler", role: .cancel) { pendingDeleteItems.removeAll() }
                    .help("Annuler la suppression")
            } message: {
                Text(deleteMessage)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(item: item) { password, expirationDate, availableDate in
                    await vm.createShareLink(
                        for: item,
                        password: password,
                        expirationDate: expirationDate,
                        availableDate: availableDate
                    )
                }
            }
            .sheet(item: $infoItem) { item in
                FileInfoSheet(vm: vm, selectedItem: item)
            }
            .sheet(isPresented: $showingShareLinks) {
                ShareLinksView(vm: vm)
            }
            .sheet(isPresented: $showingFavorites) {
                FileStationFavoritesView(vm: vm) { favorite in
                    searchText = ""
                    Task {
                        await vm.openFavorite(favorite)
                        settleAfterNavigation()
                    }
                }
            }
            .sheet(isPresented: $showingVirtualFolders) {
                FileStationVirtualFoldersView(vm: vm) { folder in
                    searchText = ""
                    Task {
                        await vm.openVirtualFolder(folder)
                        settleAfterNavigation()
                    }
                }
            }
            .sheet(isPresented: $showingTransfers) {
                FileTransfersView(vm: vm) {
                    transferTask?.cancel()
                }
            }
            .sheet(isPresented: $showingBackgroundTasks) {
                FileStationTasksView(vm: vm)
            }
            .sheet(isPresented: $showingAdvancedSearch) {
                if let folderPath = vm.currentLevel.path {
                    AdvancedFileSearchSheet(folderPath: folderPath, onSubmit: startAdvancedSearch)
                }
            }
            .sheet(isPresented: $showingPasteOptions) {
                FileConflictPolicySheet(title: "Options de collage", confirmLabel: "Coller") {
                    policy in
                    performPaste(conflictPolicy: policy)
                }
            }
            .sheet(isPresented: $showingUploadOptions, onDismiss: discardPendingUploads) {
                let counts = pendingUploadCounts
                FileUploadOptionsSheet(fileCount: counts.files, folderCount: counts.folders) {
                    options in
                    performUpload(options: options)
                }
            }
            .sheet(item: $extractionItem) { item in
                ArchiveBrowserSheet(vm: vm, archive: item) { options in
                    performExtraction(item, options: options)
                }
            }
            .onDisappear {
                transferTask?.cancel()
                advancedSearchTask?.cancel()
                operationTask?.cancel()
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.items.isEmpty {
            ModuleLoadingView()
        } else if vm.isSearching && vm.items.isEmpty {
            ModuleLoadingView("Recherche en cours…")
        } else if vm.isWorking && vm.items.isEmpty {
            ModuleLoadingView("Opération en cours…")
        } else if let error = vm.errorMessage {
            ModuleErrorView(message: error) {
                Task { await refresh() }
            }
            .accessibilityFocused($focusEmptyState)
        } else if vm.sortedItems.isEmpty {
            EmptyModuleView(
                title: vm.isShowingSearchResults ? "Aucun résultat" : "Dossier vide",
                systemImage: vm.isShowingSearchResults ? "magnifyingglass" : "folder",
                description: vm.isShowingSearchResults
                    ? "Aucun élément ne correspond à votre recherche."
                    : "Ce dossier ne contient aucun élément."
            )
            .accessibilityFocused($focusEmptyState)
        } else {
            FileTableView(
                items: vm.sortedItems,
                selection: $selection,
                focusRequestID: tableFocusRequestID,
                actionAvailability: actionAvailability,
                showsPath: vm.isShowingSearchResults,
                canExtract: vm.canExtract,
                onActivate: activate,
                onDownload: startDownload,
                onRename: { activeSheet = .rename($0) },
                onDelete: { pendingDeleteItems = $0 },
                onCopy: copyItems,
                onCut: cutItems,
                onShare: { shareItem = $0 },
                onCompress: { activeSheet = .compress($0) },
                onExtract: requestExtraction,
                onShowInfo: { infoItem = $0 },
                onGoUp: goUp,
                onPaste: dispatchPaste
            )
            .overlay(alignment: .topTrailing) {
                if vm.isSearching || vm.isWorking || vm.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .accessibilityLabel(progressLabel)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var fileToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: goUp) {
                Label("Dossier parent", systemImage: "chevron.up")
            }
            .disabled(!vm.canGoUp || vm.isLoading)
            .help("Dossier parent")
            .accessibilityHint("Remonte au dossier parent")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Nouveau dossier", systemImage: "folder.badge.plus") {
                    activeSheet = .createFolder
                }
                .disabled(!vm.canCreateFolder)
                .help("Créer un nouveau dossier")
                Button("Envoyer des fichiers…", systemImage: "square.and.arrow.up") {
                    startUpload()
                }
                .disabled(!vm.canUpload || vm.hasActiveTransfers)
                .help("Envoyer des fichiers dans ce dossier")
            } label: {
                Label("Ajouter", systemImage: "plus")
            }
            .disabled((!vm.canCreateFolder && !vm.canUpload) || vm.isWorking)
            .help("Ajouter des éléments")
        }

        ToolbarItem(placement: .primaryAction) {
            selectedItemActionsMenu
        }

        ToolbarItem(placement: .primaryAction) {
            moreOptionsMenu
        }
    }

    private var selectedItemActionsMenu: some View {
        Menu("Actions sur la sélection", systemImage: "slider.horizontal.3") {
            Button("Ouvrir", systemImage: "arrow.forward", action: activateSelection)
                .disabled(singleSelectedItem == nil)
                .help("Ouvrir l’élément sélectionné")
            Button("Télécharger…", systemImage: "square.and.arrow.down") {
                startDownload(selectedItems)
            }
            .disabled(!vm.canDownload || vm.hasActiveTransfers)
            .help("Télécharger les éléments sélectionnés")
            if selectedItems.count > 1 {
                Button("Télécharger dans une archive…", systemImage: "archivebox") {
                    startArchiveDownload(selectedItems)
                }
                .disabled(!vm.canDownload || vm.hasActiveTransfers)
                .help("Télécharger la sélection dans une seule archive ZIP")
            }
            Divider()
            Button("Copier", systemImage: "doc.on.doc") {
                copyItems(selectedItems)
            }
            .disabled(!vm.canCopyMove)
            .help("Copier les éléments sélectionnés")
            Button("Déplacer (couper)", systemImage: "scissors") {
                cutItems(selectedItems)
            }
            .disabled(!vm.canCopyMove)
            .help("Déplacer les éléments sélectionnés")
            Button("Créer un lien de partage", systemImage: "link") {
                shareItem = singleSelectedItem
            }
            .disabled(singleSelectedItem == nil || !vm.canShare)
            .help("Créer un lien vers l’élément sélectionné")
            Button("Renommer…", systemImage: "pencil") {
                if let item = singleSelectedItem { activeSheet = .rename(item) }
            }
            .disabled(singleSelectedItem == nil || !vm.canRename)
            .help("Renommer l’élément sélectionné")
            Divider()
            Button("Compresser…", systemImage: "archivebox") {
                activeSheet = .compress(selectedItems)
            }
            .disabled(!vm.canCompress)
            .help("Compresser les éléments sélectionnés")
            Button("Extraire", systemImage: "archivebox.fill") {
                if let item = singleSelectedItem { requestExtraction(item) }
            }
            .disabled(singleSelectedItem.map(vm.canExtract) != true || !vm.canExtractArchives)
            .help("Extraire l’archive sélectionnée")
            Button("Supprimer…", systemImage: "trash", role: .destructive) {
                pendingDeleteItems = selectedItems
            }
            .disabled(!vm.canDelete)
            .help("Supprimer les éléments sélectionnés")
            Divider()
            Button("Lire les informations", systemImage: "info.circle") {
                infoItem = singleSelectedItem
            }
            .disabled(singleSelectedItem == nil)
            .help("Lire les informations de l’élément sélectionné")
        }
        .disabled(selectedItems.isEmpty || vm.isWorking)
        .help("Actions sur les éléments sélectionnés")
    }

    private var moreOptionsMenu: some View {
        Menu("Plus d’options", systemImage: "ellipsis.circle") {
            Button("Coller", systemImage: "doc.on.clipboard", action: dispatchPaste)
                .disabled((!vm.canPaste && !vm.canUpload) || vm.isWorking)
                .help("Coller ici les éléments copiés ou les fichiers du Finder")

            favoritesMenu

            Button("Dossiers virtuels…", systemImage: "externaldrive") {
                showingVirtualFolders = true
            }
            .disabled(vm.availableVirtualFolderTypes.isEmpty)
            .help("Parcourir les montages NFS, CIFS et ISO de File Station")

            Button("Liens de partage", systemImage: "link") {
                showingShareLinks = true
            }
            .help("Gérer les liens de partage")

            Button("Transferts", systemImage: "arrow.up.arrow.down") {
                showingTransfers = true
            }
            .help("Afficher la progression et l’historique des transferts")

            Button("Tâches File Station", systemImage: "list.bullet.rectangle") {
                showingBackgroundTasks = true
            }
            .disabled(!vm.supports(.backgroundTasks))
            .help("Afficher et gérer les opérations exécutées par le NAS")

            Button("Recherche avancée…", systemImage: "magnifyingglass") {
                searchText = ""
                showingAdvancedSearch = true
            }
            .disabled(vm.currentLevel.path == nil || !vm.supports(.search) || vm.isSearching)
            .help("Rechercher par type, taille, date, propriétaire ou groupe")

            Divider()
            Menu("Trier", systemImage: "arrow.up.arrow.down") {
                ForEach(FileBrowserViewModel.SortMode.allCases) { mode in
                    Button {
                        vm.sortMode = mode
                    } label: {
                        if vm.sortMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                    .help(String(localized: "Trier par \(mode.title)"))
                }
                Divider()
                Button(
                    vm.sortAscending ? "Ordre décroissant" : "Ordre croissant",
                    systemImage: vm.sortAscending ? "arrow.down" : "arrow.up"
                ) {
                    vm.sortAscending.toggle()
                }
                .help(vm.sortAscending ? "Passer à l’ordre décroissant" : "Passer à l’ordre croissant")
            }
            .help("Choisir le tri des fichiers")
        }
        .help("Plus d’options pour ce dossier")
    }

    private var favoritesMenu: some View {
        Menu {
            Button("Gérer les favoris…", systemImage: "star.square") {
                showingFavorites = true
            }
            .help("Renommer, classer ou retirer des favoris")
            Divider()

            if let path = vm.currentLevel.path {
                Button {
                    Task {
                        VoiceOver.announce(await vm.toggleCurrentFavorite())
                    }
                } label: {
                    if vm.isFavorite(path: path) {
                        Label("Retirer des favoris", systemImage: "star.slash")
                    } else {
                        Label("Ajouter aux favoris", systemImage: "star")
                    }
                }
                .help(vm.isFavorite(path: path) ? "Retirer ce dossier des favoris" : "Ajouter ce dossier aux favoris")
                Divider()
            }

            if vm.favorites.isEmpty {
                if let error = vm.favoritesError {
                    Text(String(localized: "Favoris indisponibles : \(error)"))
                } else {
                    Text("Aucun favori")
                }
            } else {
                ForEach(vm.favorites) { favorite in
                    Button(favorite.name) {
                        searchText = ""
                        Task {
                            await vm.openFavorite(favorite)
                            settleAfterNavigation()
                        }
                    }
                    .disabled(!favorite.isAvailable)
                    .help(String(localized: "Ouvrir le favori \(favorite.name)"))
                }
            }
        } label: {
            Label("Favoris", systemImage: "star")
        }
        .disabled(!vm.supports(.favorites))
        .help("Favoris File Station")
    }

    @ViewBuilder
    private func writeSheet(_ sheet: WriteSheet) -> some View {
        switch sheet {
        case .createFolder:
            NameEntrySheet(
                title: "Créer un dossier",
                fieldLabel: "Nom du dossier",
                confirmLabel: "Créer",
                announcement: String(localized: "Créer un dossier")
            ) { name in
                VoiceOver.announce(
                    String(localized: "Création du dossier en cours…"),
                    category: .progress,
                    priority: .low
                )
                Task {
                    VoiceOver.announce(await vm.createFolder(named: name), priority: .high)
                }
            }
        case .rename(let item):
            NameEntrySheet(
                title: "Renommer",
                fieldLabel: "Nouveau nom",
                confirmLabel: "Renommer",
                announcement: String(localized: "Renommer « \(item.name) »"),
                initialName: item.name
            ) { name in
                VoiceOver.announce(
                    String(localized: "Modification du nom en cours…"),
                    category: .progress,
                    priority: .low
                )
                Task {
                    VoiceOver.announce(await vm.rename(item, to: name), priority: .high) {
                        selection = [item.path.deletingLastNASPathComponent.appendingNASPathComponent(name)]
                    }
                }
            }
        case .compress(let items):
            FileCompressionOptionsSheet(initialName: suggestedArchiveName(for: items)) {
                name, options in
                VoiceOver.announce(
                    String(localized: "Compression en cours…"),
                    category: .progress,
                    priority: .low
                )
                startOperation({
                    await vm.compress(items, archiveName: name, options: options)
                }) {
                    selection.removeAll()
                }
            }
        }
    }

    private var commandActions: FileCommandActions {
        FileCommandActions(
            canGoUp: vm.canGoUp,
            hasSelection: !selectedItems.isEmpty,
            hasSingleSelection: selectedItems.count == 1,
            canCreateFolder: vm.canCreateFolder && !vm.isWorking,
            canUpload: vm.canUpload && !vm.isWorking && !vm.hasActiveTransfers,
            canDownload: vm.canDownload && !vm.hasActiveTransfers,
            canCopyMove: vm.canCopyMove && !vm.isWorking,
            canRename: vm.canRename && !vm.isWorking,
            canCompress: vm.canCompress && !vm.isWorking,
            canDelete: vm.canDelete && !vm.isWorking,
            // Le presse-papiers système n'est pas observable par SwiftUI : l'élément
            // reste actif dès qu'un collage est envisageable, et un ⌘V sans contenu
            // annonce « Rien à coller. » plutôt que d'être désactivé à tort.
            canPaste: (vm.canPaste || vm.canUpload) && !vm.isWorking,
            canExtract: selectedItems.count == 1
                && vm.canExtract(selectedItems[0])
                && vm.canExtractArchives
                && !vm.isWorking,
            refresh: { Task { await refresh() } },
            goUp: goUp,
            open: activateSelection,
            createFolder: { activeSheet = .createFolder },
            upload: startUpload,
            download: { startDownload(selectedItems) },
            rename: { if let item = singleSelectedItem { activeSheet = .rename(item) } },
            copy: { copyItems(selectedItems) },
            cut: { cutItems(selectedItems) },
            paste: dispatchPaste,
            compress: { activeSheet = .compress(selectedItems) },
            extract: { if let item = singleSelectedItem { requestExtraction(item) } },
            delete: { pendingDeleteItems = selectedItems },
            showInfo: { infoItem = singleSelectedItem }
        )
    }

    private var selectedItems: [FileStationItem] {
        vm.sortedItems.filter { selection.contains($0.path) }
    }

    private var actionAvailability: FileActionAvailability {
        FileActionAvailability(
            canDownload: vm.canDownload && !vm.hasActiveTransfers,
            canRename: vm.canRename && !vm.isWorking,
            canDelete: vm.canDelete && !vm.isWorking,
            canCopyMove: vm.canCopyMove && !vm.isWorking,
            canShare: vm.canShare && !vm.isWorking,
            canCompress: vm.canCompress && !vm.isWorking,
            canExtract: vm.canExtractArchives && !vm.isWorking
        )
    }

    private var singleSelectedItem: FileStationItem? {
        selectedItems.count == 1 ? selectedItems[0] : nil
    }

    private var progressLabel: String {
        if vm.isSearching, let progress = vm.searchProgress, progress.total > 0 {
            return String(localized: "Recherche en cours, résultats trouvés : \(progress.total)")
        }
        if vm.isSearching { return String(localized: "Recherche en cours…") }
        if vm.isDownloading { return String(localized: "Téléchargement en cours…") }
        return String(localized: "Opération en cours…")
    }

    private var deleteTitle: String {
        pendingDeleteItems.count == 1
            ? String(localized: "Supprimer cet élément ?")
            : String(localized: "Supprimer \(pendingDeleteItems.count) éléments ?")
    }

    private var deleteMessage: String {
        if pendingDeleteItems.count == 1, let item = pendingDeleteItems.first {
            return String(localized: "« \(item.name) » sera supprimé définitivement. Cette action est irréversible.")
        }
        return String(localized: "Les éléments sélectionnés seront supprimés définitivement. Cette action est irréversible.")
    }

    private func activate(_ item: FileStationItem) {
        if item.isdir {
            searchText = ""
            Task {
                await vm.open(item)
                settleAfterNavigation()
            }
        } else {
            startDownload([item])
        }
    }

    private func activateSelection() {
        guard let item = singleSelectedItem else { return }
        activate(item)
    }

    private func goUp() {
        guard vm.canGoUp else { return }
        searchText = ""
        Task {
            await vm.goUp()
            settleAfterNavigation()
        }
    }

    private func refresh() async {
        await vm.reloadCurrentSearch(simpleQuery: searchText)
        announceSummary()
    }

    private func startAdvancedSearch(_ criteria: FileStationSearchCriteria) {
        advancedSearchTask?.cancel()
        VoiceOver.announce(
            String(localized: "Recherche avancée en cours…"),
            category: .progress,
            priority: .low
        )
        advancedSearchTask = Task {
            await vm.search(criteria)
            guard !Task.isCancelled else { return }
            selection.removeAll()
            announceSummary()
            advancedSearchTask = nil
        }
    }

    private func copyItems(_ items: [FileStationItem]) {
        let message = vm.copy(items)
        FinderPasteboard.write(items: items, viewModel: vm)
        VoiceOver.announce(
            "\(message) \(String(localized: "Collage possible ici ou dans le Finder."))",
            category: .result
        )
    }

    private func cutItems(_ items: [FileStationItem]) {
        let message = vm.cut(items)
        FinderPasteboard.claimForInternalCut()
        VoiceOver.announce(message, category: .result)
    }

    private func dispatchPaste() {
        guard !vm.isWorking else { return }
        switch FinderPasteboard.currentIntent(hasInternalClipboard: vm.canPaste) {
        case .uploadFinderFiles(let urls):
            requestFinderUpload(urls)
        case .pasteInternalClipboard:
            requestPaste()
        case .nothing:
            VoiceOver.announce(String(localized: "Rien à coller."), category: .result)
        }
    }

    private func requestFinderUpload(_ urls: [URL]) {
        guard vm.canUpload else {
            VoiceOver.announce(
                String(localized: "Impossible d’envoyer ici."),
                category: .error,
                priority: .high
            )
            return
        }
        guard !vm.hasActiveTransfers else {
            VoiceOver.announce(
                String(localized: "Attendez la fin des transferts en cours avant de coller des fichiers."),
                category: .error,
                priority: .high
            )
            return
        }
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        pendingUploadURLs = urls
        showingUploadOptions = true
    }

    private func requestPaste() {
        guard vm.canPaste, !vm.isWorking else { return }
        showingPasteOptions = true
    }

    private func performPaste(conflictPolicy: FileConflictPolicy) {
        VoiceOver.announce(
            String(localized: "Collage en cours…"),
            category: .progress,
            priority: .low
        )
        startOperation({ await vm.paste(conflictPolicy: conflictPolicy) }) {
            selection.removeAll()
        }
    }

    private func requestExtraction(_ item: FileStationItem) {
        extractionItem = item
    }

    private func performExtraction(
        _ item: FileStationItem,
        options: FileStationExtractionOptions
    ) {
        VoiceOver.announce(
            String(localized: "Extraction en cours…"),
            category: .progress,
            priority: .low
        )
        startOperation({ await vm.extract(item, options: options) }) {
            selection.removeAll()
        }
    }

    private func startDownload(_ items: [FileStationItem]) {
        guard !items.isEmpty, !vm.hasActiveTransfers else { return }
        if items.count == 1, let item = items.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = vm.suggestedFilename(for: item)
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            _ = url.startAccessingSecurityScopedResource()
            VoiceOver.announce(
                String(localized: "Téléchargement en cours…"),
                category: .progress,
                priority: .low
            )
            showingTransfers = true
            transferTask = Task {
                let outcome = await vm.download(item, to: url)
                VoiceOver.announce(outcome, priority: .high)
                transferTask = nil
            }
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choisir")
        panel.message = String(localized: "Choisissez le dossier de destination des téléchargements.")
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        _ = directory.startAccessingSecurityScopedResource()
        VoiceOver.announce(
            String(localized: "Téléchargements en cours…"),
            category: .progress,
            priority: .low
        )
        showingTransfers = true
        transferTask = Task {
            let outcome = await vm.download(items, to: directory)
            VoiceOver.announce(outcome, priority: .high)
            transferTask = nil
        }
    }

    private func startArchiveDownload(_ items: [FileStationItem]) {
        guard items.count > 1, !vm.hasActiveTransfers else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Archive File Station.zip")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]
        panel.message = String(
            localized: "File Station regroupera les éléments sélectionnés dans une seule archive ZIP."
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        VoiceOver.announce(
            String(localized: "Téléchargement de l’archive en cours…"),
            category: .progress,
            priority: .low
        )
        showingTransfers = true
        transferTask = Task {
            let outcome = await vm.downloadAsArchive(items, to: url)
            VoiceOver.announce(outcome, priority: .high)
            transferTask = nil
        }
    }

    private var pendingUploadCounts: (files: Int, folders: Int) {
        pendingUploadURLs.reduce(into: (files: 0, folders: 0)) { counts, url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            if isDirectory == true {
                counts.folders += 1
            } else {
                counts.files += 1
            }
        }
    }

    private func startUpload() {
        guard vm.canWrite, !vm.hasActiveTransfers else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Envoyer")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        for url in panel.urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        pendingUploadURLs = panel.urls
        showingUploadOptions = true
    }

    private func performUpload(options: FileStationUploadOptions) {
        let urls = pendingUploadURLs
        pendingUploadURLs.removeAll()
        guard !urls.isEmpty else { return }
        VoiceOver.announce(
            String(localized: "Envoi en cours…"),
            category: .progress,
            priority: .low
        )
        showingTransfers = true
        transferTask = Task {
            let outcome = await vm.upload(urls: urls, options: options)
            VoiceOver.announce(outcome, priority: .high)
            transferTask = nil
        }
    }

    private func discardPendingUploads() {
        for url in pendingUploadURLs {
            url.stopAccessingSecurityScopedResource()
        }
        pendingUploadURLs.removeAll()
    }

    private func startOperation(
        _ operation: @escaping @MainActor () async -> DSMOperationOutcome,
        onSuccess: @escaping @MainActor () -> Void = {}
    ) {
        operationTask?.cancel()
        operationTask = Task {
            let outcome = await operation()
            guard !Task.isCancelled else {
                operationTask = nil
                return
            }
            VoiceOver.announce(outcome, priority: .high) {
                onSuccess()
            }
            operationTask = nil
        }
    }

    private func cancelOperation() {
        operationTask?.cancel()
        VoiceOver.announce(
            String(localized: "Annulation de l’opération demandée"),
            category: .progress,
            priority: .high
        )
    }

    private func suggestedArchiveName(for items: [FileStationItem]) -> String {
        guard items.count == 1, let item = items.first else {
            return String(localized: "Archive.zip")
        }
        return "\(item.name).zip"
    }

    private func settleAfterNavigation() {
        if vm.errorMessage != nil {
            selection.removeAll()
            focusEmptyState = true
        } else if let firstItem = vm.sortedItems.first {
            focusEmptyState = false
            selection = [firstItem.path]
            tableFocusRequestID += 1
        } else {
            selection.removeAll()
            focusEmptyState = true
        }
        announceSummary(category: .navigation)
    }

    private func restoreInitialContentFocus() {
        if vm.errorMessage != nil || vm.sortedItems.isEmpty {
            focusEmptyState = true
        } else if let firstItem = vm.sortedItems.first {
            focusEmptyState = false
            selection = [firstItem.path]
            tableFocusRequestID += 1
        }
    }

    private func announceSummary(category: AnnouncementCategory = .result) {
        VoiceOver.announce(
            vm.summary,
            category: vm.errorMessage == nil ? category : .error
        )
    }
}

private extension String {
    var deletingLastNASPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }

    func appendingNASPathComponent(_ component: String) -> String {
        hasSuffix("/") ? self + component : self + "/" + component
    }
}
