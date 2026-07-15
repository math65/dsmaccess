//
//  FileBrowserView.swift
//  dsmaccess
//
//  Native Mac shell for File Station: toolbar, search, favourites, multi-selection,
//  file panels and accessible operation feedback.
//

import AppKit
import SwiftUI

struct FileBrowserView: View {
    @State private var vm: FileBrowserViewModel
    @State private var selection = Set<String>()
    @State private var searchText = ""
    @State private var activeSheet: WriteSheet?
    @State private var pendingDeleteItems = [FileStationItem]()
    @State private var shareItem: FileStationItem?
    @State private var infoItem: FileStationItem?
    @State private var showingShareLinks = false
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
        content
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
                announceSummary()
            }
            .task(id: searchText) {
                do {
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try await Task.sleep(for: .milliseconds(300))
                    }
                    try Task.checkCancellation()
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    Task {
                        let message = await vm.delete(items)
                        selection.removeAll()
                        VoiceOver.announce(message, priority: .high)
                    }
                }
                .help("Supprimer définitivement les éléments sélectionnés")
                Button("Annuler", role: .cancel) { pendingDeleteItems.removeAll() }
                    .help("Annuler la suppression")
            } message: {
                Text(deleteMessage)
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(item: item) { password, dateExpired in
                    await vm.createShareLink(for: item, password: password, dateExpired: dateExpired)
                }
            }
            .sheet(item: $infoItem) { item in
                FileInfoSheet(item: item)
            }
            .sheet(isPresented: $showingShareLinks) {
                ShareLinksView(vm: vm)
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
                canWrite: vm.canWrite && !vm.isWorking,
                showsPath: vm.isShowingSearchResults,
                canExtract: vm.canExtract,
                onActivate: activate,
                onDownload: startDownload,
                onRename: { activeSheet = .rename($0) },
                onDelete: { pendingDeleteItems = $0 },
                onCopy: { VoiceOver.announce(vm.copy($0)) },
                onCut: { VoiceOver.announce(vm.cut($0)) },
                onShare: { shareItem = $0 },
                onCompress: { activeSheet = .compress($0) },
                onExtract: extract,
                onShowInfo: { infoItem = $0 },
                onGoUp: goUp
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
                .help("Créer un nouveau dossier")
                Button("Envoyer des fichiers…", systemImage: "square.and.arrow.up") {
                    startUpload()
                }
                .help("Envoyer des fichiers dans ce dossier")
            } label: {
                Label("Ajouter", systemImage: "plus")
            }
            .disabled(!vm.canWrite || vm.isWorking)
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
            .help("Télécharger les éléments sélectionnés")
            Divider()
            Button("Copier", systemImage: "doc.on.doc") {
                VoiceOver.announce(vm.copy(selectedItems), category: .result)
            }
            .disabled(!vm.canWrite)
            .help("Copier les éléments sélectionnés")
            Button("Déplacer (couper)", systemImage: "scissors") {
                VoiceOver.announce(vm.cut(selectedItems), category: .result)
            }
            .disabled(!vm.canWrite)
            .help("Déplacer les éléments sélectionnés")
            Button("Créer un lien de partage", systemImage: "link") {
                shareItem = singleSelectedItem
            }
            .disabled(singleSelectedItem == nil || !vm.canWrite)
            .help("Créer un lien vers l’élément sélectionné")
            Button("Renommer…", systemImage: "pencil") {
                if let item = singleSelectedItem { activeSheet = .rename(item) }
            }
            .disabled(singleSelectedItem == nil || !vm.canWrite)
            .help("Renommer l’élément sélectionné")
            Divider()
            Button("Compresser…", systemImage: "archivebox") {
                activeSheet = .compress(selectedItems)
            }
            .disabled(!vm.canWrite)
            .help("Compresser les éléments sélectionnés")
            Button("Extraire", systemImage: "archivebox.fill") {
                if let item = singleSelectedItem { extract(item) }
            }
            .disabled(singleSelectedItem.map(vm.canExtract) != true || !vm.canWrite)
            .help("Extraire l’archive sélectionnée")
            Button("Supprimer…", systemImage: "trash", role: .destructive) {
                pendingDeleteItems = selectedItems
            }
            .disabled(!vm.canWrite)
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
            Button("Coller", systemImage: "doc.on.clipboard", action: paste)
                .disabled(!vm.canPaste || vm.isWorking)
                .help("Coller dans ce dossier")

            favoritesMenu

            Button("Liens de partage", systemImage: "link") {
                showingShareLinks = true
            }
            .help("Gérer les liens de partage")

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
            if let path = vm.currentLevel.path {
                Button {
                    Task {
                        let message = await vm.toggleCurrentFavorite()
                        VoiceOver.announce(message)
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
                Text("Aucun favori")
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
                    let message = await vm.createFolder(named: name)
                    VoiceOver.announce(message, priority: .high)
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
                    let message = await vm.rename(item, to: name)
                    selection = [item.path.deletingLastNASPathComponent.appendingNASPathComponent(name)]
                    VoiceOver.announce(message, priority: .high)
                }
            }
        case .compress(let items):
            NameEntrySheet(
                title: "Compresser",
                fieldLabel: "Nom de l’archive",
                confirmLabel: "Créer l’archive",
                announcement: String(localized: "Créer une archive"),
                initialName: suggestedArchiveName(for: items)
            ) { name in
                VoiceOver.announce(
                    String(localized: "Compression en cours…"),
                    category: .progress,
                    priority: .low
                )
                Task {
                    let message = await vm.compress(items, archiveName: name)
                    selection.removeAll()
                    VoiceOver.announce(message, priority: .high)
                }
            }
        }
    }

    private var commandActions: FileCommandActions {
        FileCommandActions(
            canGoUp: vm.canGoUp,
            hasSelection: !selectedItems.isEmpty,
            hasSingleSelection: selectedItems.count == 1,
            canWrite: vm.canWrite && !vm.isWorking,
            canPaste: vm.canPaste && !vm.isWorking,
            canExtract: selectedItems.count == 1 && vm.canExtract(selectedItems[0]),
            refresh: { Task { await refresh() } },
            goUp: goUp,
            open: activateSelection,
            createFolder: { activeSheet = .createFolder },
            upload: startUpload,
            download: { startDownload(selectedItems) },
            rename: { if let item = singleSelectedItem { activeSheet = .rename(item) } },
            copy: { VoiceOver.announce(vm.copy(selectedItems)) },
            cut: { VoiceOver.announce(vm.cut(selectedItems)) },
            paste: paste,
            compress: { activeSheet = .compress(selectedItems) },
            extract: { if let item = singleSelectedItem { extract(item) } },
            delete: { pendingDeleteItems = selectedItems },
            showInfo: { infoItem = singleSelectedItem }
        )
    }

    private var selectedItems: [FileStationItem] {
        vm.sortedItems.filter { selection.contains($0.path) }
    }

    private var singleSelectedItem: FileStationItem? {
        selectedItems.count == 1 ? selectedItems[0] : nil
    }

    private var progressLabel: String {
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
        await vm.loadCurrent()
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await vm.search(searchText)
        }
        announceSummary()
    }

    private func paste() {
        VoiceOver.announce(
            String(localized: "Collage en cours…"),
            category: .progress,
            priority: .low
        )
        Task {
            let message = await vm.paste()
            selection.removeAll()
            VoiceOver.announce(message, priority: .high)
        }
    }

    private func extract(_ item: FileStationItem) {
        VoiceOver.announce(
            String(localized: "Extraction en cours…"),
            category: .progress,
            priority: .low
        )
        Task {
            let message = await vm.extract(item)
            selection.removeAll()
            VoiceOver.announce(message, priority: .high)
        }
    }

    private func startDownload(_ items: [FileStationItem]) {
        guard !items.isEmpty else { return }
        if items.count == 1, let item = items.first {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = vm.suggestedFilename(for: item)
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            VoiceOver.announce(
                String(localized: "Téléchargement en cours…"),
                category: .progress,
                priority: .low
            )
            Task {
                let message = await vm.download(item, to: url)
                VoiceOver.announce(message, priority: .high)
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
        VoiceOver.announce(
            String(localized: "Téléchargements en cours…"),
            category: .progress,
            priority: .low
        )
        Task {
            let message = await vm.download(items, to: directory)
            VoiceOver.announce(message, priority: .high)
        }
    }

    private func startUpload() {
        guard vm.canWrite else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Envoyer")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        VoiceOver.announce(
            String(localized: "Envoi en cours…"),
            category: .progress,
            priority: .low
        )
        Task {
            let message = await vm.upload(fileURLs: panel.urls)
            VoiceOver.announce(message, priority: .high)
        }
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
        announceSummary()
    }

    private func announceSummary() {
        VoiceOver.announce(
            vm.summary,
            category: vm.errorMessage == nil ? .result : .error
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
