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
    /// Everything the conflict sheet needs, captured at the time of the gesture: the folder
    /// targeted then rather than the one on screen when the user confirms, and the names that
    /// are about to be replaced. Carried by the presentation itself — a separate `@State`
    /// read at draw time can already have moved on, and the sheet then names nothing.
    @State private var pasteConflict: PasteConflict?
    @State private var uploadConflict: UploadConflict?
    @State private var pendingUploadURLs = [URL]()
    @State private var extractionItem: FileStationItem?
    @State private var transferTask: Task<Void, Never>?
    @State private var advancedSearchTask: Task<Void, Never>?
    @State private var operationTask: Task<Void, Never>?
    @State private var stopTask: Task<Void, Never>?
    @State private var tableFocusRequestID = 0
    @AccessibilityFocusState private var focusEmptyState: Bool

    private struct PasteConflict: Identifiable {
        let destination: String
        let moving: Bool
        let names: [String]
        var id: String { "\(moving)-\(destination)-\(names.joined(separator: "|"))" }
    }

    private struct UploadConflict: Identifiable {
        let names: [String]
        var id: String { names.joined(separator: "|") }
    }

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
                    bytesPerSecond: vm.operationBytesPerSecond,
                    timeRemaining: vm.operationTimeRemaining,
                    cancel: cancelOperation
                )
            }
            if let summary = vm.operationSummary {
                FileOperationSummaryBanner(
                    summary: summary,
                    showBackgroundTasks: { showingBackgroundTasks = true },
                    dismiss: vm.dismissOperationSummary
                )
            }
            content
        }
            .navigationTitle(vm.title)
            .searchable(text: $searchText, prompt: "files.search.placeholder")
            .toolbar { fileToolbar }
            .focusedSceneValue(\.fileCommandActions, commandActions)
            .task {
                VoiceOver.announce(
                    String(localized: "files.progress.loading"),
                    category: .progress,
                    priority: .low
                )
                await vm.loadCurrent()
                guard !Task.isCancelled else { return }
                await vm.loadFavorites()
                await VoiceOver.restoreFocusIfCapturedByToolbar(restoreInitialContentFocus)
                announceSummary()
                resumeUnfinishedOperation()
            }
            .task(id: searchText) {
                // On first display this task starts with an empty field, before loading has
                // finished: with no search to run and none to clear, announce nothing
                // (otherwise VoiceOver hears "Empty folder" and then the real contents).
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if query.isEmpty && !vm.isShowingSearchResults { return }
                do {
                    if !query.isEmpty {
                        try await Task.sleep(for: .milliseconds(300))
                    }
                    try Task.checkCancellation()
                    if !query.isEmpty {
                        VoiceOver.announce(
                            String(localized: "files.progress.searching"),
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
                Button("common.button.delete", role: .destructive) {
                    let items = pendingDeleteItems
                    pendingDeleteItems.removeAll()
                    startOperation({ await vm.delete(items) }) {
                        selection.removeAll()
                    }
                }
                .help("files.delete.button.hint")
                Button("common.button.cancel", role: .cancel) { pendingDeleteItems.removeAll() }
                    .help("common.button.cancel_deletion")
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
            .sheet(item: $pasteConflict) { conflict in
                FileConflictPolicySheet(
                    title: conflict.moving
                        ? String(localized: "files.button.move_into", defaultValue: "Move into \(conflict.destination)")
                        : String(localized: "files.button.paste_into", defaultValue: "Paste into \(conflict.destination)"),
                    conflictingNames: conflict.names,
                    confirmLabel: conflict.moving ? "files.button.move" : "common.button.paste"
                ) { policy in
                    performPaste(moving: conflict.moving, conflictPolicy: policy)
                }
            }
            .sheet(item: $uploadConflict, onDismiss: discardPendingUploads) { conflict in
                FileConflictPolicySheet(
                    title: String(localized: "files.upload.options.title"),
                    conflictingNames: conflict.names,
                    confirmLabel: "common.button.upload"
                ) { policy in
                    performUpload(options: FileStationUploadOptions(conflictPolicy: policy))
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
            ModuleLoadingView("files.progress.searching")
        } else if vm.isWorking && vm.items.isEmpty {
            ModuleLoadingView("files.progress.working")
        } else if let error = vm.errorMessage {
            ModuleErrorView(message: error) {
                Task { await refresh() }
            }
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
                onShare: { shareItem = $0 },
                onCompress: { activeSheet = .compress($0) },
                onExtract: requestExtraction,
                onShowInfo: { infoItem = $0 },
                onGoUp: goUp,
                onPaste: dispatchPaste,
                onMoveHere: dispatchMove,
                makeDragProvider: { FinderPasteboard.dragProvider(for: $0, viewModel: vm) }
            )
            .overlay(alignment: .topTrailing) {
                if vm.isSearching || vm.isWorking || vm.isDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                        .accessibilityLabel(progressLabel)
                }
            }
            // The empty state covers the table instead of replacing it. Replacing it took the
            // table's keyboard handling down with it, and ⌘V did nothing in exactly the folder
            // where pasting matters most.
            .overlay {
                if vm.sortedItems.isEmpty {
                    EmptyModuleView(
                        title: vm.isShowingSearchResults ? "common.empty.results" : "common.empty.folder",
                        systemImage: vm.isShowingSearchResults ? "magnifyingglass" : "folder",
                        description: vm.isShowingSearchResults
                            ? "files.search.empty"
                            : "common.empty.folder.description"
                    )
                    .background(.background)
                    .accessibilityFocused($focusEmptyState)
                    // The message is there to be read, not clicked: swallowing mouse events
                    // would keep the table underneath from ever taking keyboard focus.
                    .allowsHitTesting(false)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var fileToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: goUp) {
                Label("common.button.parent_folder", systemImage: "chevron.up")
            }
            .disabled(!vm.canGoUp || vm.isLoading)
            .help("common.button.parent_folder")
            .accessibilityHint("files.button.parent_folder.hint")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("common.button.new_folder", systemImage: "folder.badge.plus") {
                    activeSheet = .createFolder
                }
                .disabled(!vm.canCreateFolder)
                .help("common.button.new_folder.hint")
                Button("common.button.upload_files", systemImage: "square.and.arrow.up") {
                    startUpload()
                }
                .disabled(!vm.canUpload || vm.hasActiveTransfers)
                .help("common.button.upload_files.hint")
            } label: {
                Label("common.button.add", systemImage: "plus")
            }
            .disabled((!vm.canCreateFolder && !vm.canUpload) || vm.isWorking)
            .help("files.menu.add_items")
        }

        ToolbarItem(placement: .primaryAction) {
            selectedItemActionsMenu
        }

        ToolbarItem(placement: .primaryAction) {
            moreOptionsMenu
        }
    }

    private var selectedItemActionsMenu: some View {
        Menu("files.menu.selection_actions.label", systemImage: "slider.horizontal.3") {
            Button("common.button.open", systemImage: "arrow.forward", action: activateSelection)
                .disabled(singleSelectedItem == nil)
                .help("common.button.open.hint")
            Button("common.button.download", systemImage: "square.and.arrow.down") {
                startDownload(selectedItems)
            }
            .disabled(!vm.canDownload || vm.hasActiveTransfers)
            .help("common.button.download.hint")
            if selectedItems.count > 1 {
                Button("files.button.download_as_archive", systemImage: "archivebox") {
                    startArchiveDownload(selectedItems)
                }
                .disabled(!vm.canDownload || vm.hasActiveTransfers)
                .help("files.button.download_as_archive.hint")
            }
            Divider()
            Button("common.button.copy", systemImage: "doc.on.doc") {
                copyItems(selectedItems)
            }
            .disabled(!vm.canCopyMove)
            .help("common.button.copy.hint")
            Button("common.action.create_share_link", systemImage: "link") {
                shareItem = singleSelectedItem
            }
            .disabled(singleSelectedItem == nil || !vm.canShare)
            .help("files.share_link.create.hint")
            Button("common.menu.rename", systemImage: "pencil") {
                if let item = singleSelectedItem { activeSheet = .rename(item) }
            }
            .disabled(singleSelectedItem == nil || !vm.canRename)
            .help("common.button.rename.hint")
            Divider()
            Button("common.button.compress", systemImage: "archivebox") {
                activeSheet = .compress(selectedItems)
            }
            .disabled(!vm.canCompress)
            .help("common.button.compress.hint")
            Button("common.button.extract", systemImage: "archivebox.fill") {
                if let item = singleSelectedItem { requestExtraction(item) }
            }
            .disabled(singleSelectedItem.map(vm.canExtract) != true || !vm.canExtractArchives)
            .help("common.button.extract.hint")
            Button("common.menu.delete", systemImage: "trash", role: .destructive) {
                pendingDeleteItems = selectedItems
            }
            .disabled(!vm.canDelete)
            .help("common.button.delete.hint")
            Divider()
            Button("common.button.get_info", systemImage: "info.circle") {
                infoItem = singleSelectedItem
            }
            .disabled(singleSelectedItem == nil)
            .help("common.button.get_info.hint")
        }
        .disabled(selectedItems.isEmpty || vm.isWorking)
        .help("files.menu.selection_actions.hint")
    }

    private var moreOptionsMenu: some View {
        Menu("common.button.more_options", systemImage: "ellipsis.circle") {
            Button("common.button.paste", systemImage: "doc.on.clipboard", action: dispatchPaste)
                .disabled((!vm.canPaste && !vm.canUpload) || vm.isWorking)
                .help("common.button.paste.hint")
            Button("common.button.move_here", systemImage: "arrow.forward.doc.on.clipboard", action: dispatchMove)
                .disabled(!vm.canPaste || vm.isWorking)
                .help("common.button.move_here.hint")

            favoritesMenu

            Button("files.button.virtual_folders", systemImage: "externaldrive") {
                showingVirtualFolders = true
            }
            .disabled(vm.availableVirtualFolderTypes.isEmpty)
            .help("files.virtual_folders.hint")

            Button("common.action.share_links", systemImage: "link") {
                showingShareLinks = true
            }
            .help("files.menu.manage_share_links")

            Button("common.label.transfers", systemImage: "arrow.up.arrow.down") {
                showingTransfers = true
            }
            .help("files.button.transfers.hint")

            Button("common.action.file_station_tasks", systemImage: "list.bullet.rectangle") {
                showingBackgroundTasks = true
            }
            .disabled(!vm.supports(.backgroundTasks))
            .help("common.action.file_station_tasks.hint")

            Button("files.button.advanced_search", systemImage: "magnifyingglass") {
                searchText = ""
                showingAdvancedSearch = true
            }
            .disabled(vm.currentLevel.path == nil || !vm.supports(.search) || vm.isSearching)
            .help("files.button.advanced_search.hint")

            Divider()
            Menu("files.sort.menu.label", systemImage: "arrow.up.arrow.down") {
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
                    .help(String(localized: "files.sort.by", defaultValue: "Sort by \(mode.title)"))
                }
                Divider()
                Button(
                    vm.sortAscending ? "files.sort.descending.label" : "common.sort.ascending",
                    systemImage: vm.sortAscending ? "arrow.down" : "arrow.up"
                ) {
                    vm.sortAscending.toggle()
                }
                .help(vm.sortAscending ? "files.sort.switch_descending.hint" : "files.sort.switch_ascending.hint")
            }
            .help("files.sort.menu.hint")
        }
        .help("files.menu.folder_options.hint")
    }

    private var favoritesMenu: some View {
        Menu {
            Button("files.menu.manage_favorites", systemImage: "star.square") {
                showingFavorites = true
            }
            .help("files.menu.manage_favorites.hint")
            Divider()

            if let path = vm.currentLevel.path {
                Button {
                    Task {
                        VoiceOver.announce(await vm.toggleCurrentFavorite())
                    }
                } label: {
                    if vm.isFavorite(path: path) {
                        Label("files.favorites.remove.label", systemImage: "star.slash")
                    } else {
                        Label("files.favorites.add.label", systemImage: "star")
                    }
                }
                .help(vm.isFavorite(path: path) ? "files.favorites.remove.hint" : "files.favorites.add.hint")
                Divider()
            }

            if vm.favorites.isEmpty {
                if let error = vm.favoritesError {
                    Text(String(localized: "files.favorites.unavailable.error", defaultValue: "Favorites unavailable: \(error)"))
                } else {
                    Text("common.empty.favorites")
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
                    .help(String(localized: "files.favorites.open.hint", defaultValue: "Open the \(favorite.name) favorite"))
                }
            }
        } label: {
            Label("files.favorites.title", systemImage: "star")
        }
        .disabled(!vm.supports(.favorites))
        .help("common.action.file_station_favorites")
    }

    @ViewBuilder
    private func writeSheet(_ sheet: WriteSheet) -> some View {
        switch sheet {
        case .createFolder:
            NameEntrySheet(
                title: "files.button.new_folder",
                fieldLabel: "files.new_folder.name.label",
                confirmLabel: "common.button.create",
                announcement: String(localized: "files.button.new_folder")
            ) { name in
                VoiceOver.announce(
                    String(localized: "files.progress.creating_folder"),
                    category: .progress,
                    priority: .low
                )
                Task {
                    VoiceOver.announce(await vm.createFolder(named: name), priority: .high)
                }
            }
        case .rename(let item):
            NameEntrySheet(
                title: "common.button.rename",
                fieldLabel: "files.rename.name.label",
                confirmLabel: "common.button.rename",
                announcement: String(localized: "files.rename.dialog.title", defaultValue: "Rename “\(item.name)”"),
                initialName: item.name
            ) { name in
                VoiceOver.announce(
                    String(localized: "files.progress.renaming"),
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
                    String(localized: "files.progress.compressing"),
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
            // The system pasteboard is not observable by SwiftUI: the item stays enabled as
            // soon as a paste is conceivable, and a ⌘V with nothing to paste announces
            // "Nothing to paste." rather than being wrongly disabled.
            canPaste: (vm.canPaste || vm.canUpload) && !vm.isWorking,
            canMoveHere: vm.canPaste && !vm.isWorking,
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
            paste: dispatchPaste,
            moveHere: dispatchMove,
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
            return String(localized: "files.search.progress.results", defaultValue: "Search in progress, results found: \(progress.total)")
        }
        if vm.isSearching { return String(localized: "files.progress.searching") }
        if vm.isDownloading { return String(localized: "files.progress.downloading_single") }
        return String(localized: "files.progress.working")
    }

    private var deleteTitle: String {
        pendingDeleteItems.count == 1
            ? String(localized: "files.delete.confirm.title_single")
            : String(localized: "files.delete.confirm.title_multiple", defaultValue: "Delete \(pendingDeleteItems.count) Items?")
    }

    private var deleteMessage: String {
        if pendingDeleteItems.count == 1, let item = pendingDeleteItems.first {
            return String(localized: "files.delete.confirm.message_single", defaultValue: "“\(item.name)” will be permanently deleted. This action cannot be undone.")
        }
        return String(localized: "files.delete.confirm.message_multiple")
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
            String(localized: "files.advanced_search.progress"),
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
        FinderPasteboard.claimForInternalClipboard()
        VoiceOver.announce(message, category: .result)
    }

    private func dispatchPaste() {
        guard !vm.isWorking else { return }
        switch FinderPasteboard.currentIntent(hasInternalClipboard: vm.canPaste) {
        case .uploadFinderFiles(let urls):
            requestFinderUpload(urls)
        case .pasteInternalClipboard:
            requestPaste(moving: false)
        case .nothing:
            VoiceOver.announce(String(localized: "common.error.nothing_to_paste"), category: .result)
        }
    }

    /// ⌘⌥V, as in the Finder. Moving files from the Mac would mean deleting them after the
    /// upload: the gesture is reserved for the internal clipboard.
    private func dispatchMove() {
        guard !vm.isWorking else { return }
        switch FinderPasteboard.currentIntent(hasInternalClipboard: vm.canPaste) {
        case .uploadFinderFiles:
            VoiceOver.announce(
                String(localized: "files.drop.finder_move.error"),
                category: .error,
                priority: .high
            )
        case .pasteInternalClipboard:
            requestPaste(moving: true)
        case .nothing:
            VoiceOver.announce(String(localized: "files.move.empty"), category: .result)
        }
    }

    private func requestFinderUpload(_ urls: [URL]) {
        guard vm.canUpload else {
            VoiceOver.announce(
                String(localized: "common.error.upload_not_allowed_here"),
                category: .error,
                priority: .high
            )
            return
        }
        guard !vm.hasActiveTransfers else {
            VoiceOver.announce(
                String(localized: "files.paste.transfers_busy.error"),
                category: .error,
                priority: .high
            )
            return
        }
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        pendingUploadURLs = urls
        // Nothing to decide when no name collides: DSM asks nothing when you drop a file, and
        // neither does the Finder. The sheet is for the one question that has an answer worth
        // giving — replace what is already there, or keep it.
        let existing = vm.existingNames(among: urls.map(\.lastPathComponent))
        if existing.isEmpty {
            performUpload(options: FileStationUploadOptions(conflictPolicy: .skip))
        } else {
            uploadConflict = UploadConflict(names: existing)
        }
    }

    private func requestPaste(moving: Bool) {
        guard vm.canPaste, !vm.isWorking, let destination = vm.currentLevel.path else { return }
        let existing = vm.existingNames(among: vm.clipboard?.items.map(\.name) ?? [])
        if existing.isEmpty {
            performPaste(moving: moving, conflictPolicy: .skip)
        } else {
            pasteConflict = PasteConflict(
                destination: destination,
                moving: moving,
                names: existing
            )
        }
    }

    private func performPaste(moving: Bool, conflictPolicy: FileConflictPolicy) {
        VoiceOver.announce(
            moving
                ? String(localized: "files.progress.moving")
                : String(localized: "files.progress.pasting"),
            category: .progress,
            priority: .low
        )
        startOperation({ await vm.paste(moving: moving, conflictPolicy: conflictPolicy) }) {
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
            String(localized: "files.progress.extracting"),
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
            // A folder comes back as an archive built by the NAS. Saying so beforehand spares
            // the surprise of finding a .zip where a folder was expected.
            VoiceOver.announce(
                item.isdir
                    ? String(
                        localized: "files.download.folder_as_archive.announcement",
                        defaultValue: "The folder will be downloaded as the archive \(vm.suggestedFilename(for: item))"
                    )
                    : String(localized: "files.progress.downloading_single"),
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
        panel.prompt = String(localized: "files.button.choose")
        panel.message = String(localized: "files.download_destination.description")
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        _ = directory.startAccessingSecurityScopedResource()
        VoiceOver.announce(
            String(localized: "files.progress.downloading_multiple"),
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
        panel.nameFieldStringValue = String(localized: "files.archive.default_name")
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.zip]
        panel.message = String(
            localized: "files.compress.description"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        VoiceOver.announce(
            String(localized: "files.progress.downloading_archive"),
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

    private func startUpload() {
        guard vm.canWrite, !vm.hasActiveTransfers else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "common.button.upload")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        for url in panel.urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        pendingUploadURLs = panel.urls
        let existing = vm.existingNames(among: panel.urls.map(\.lastPathComponent))
        if existing.isEmpty {
            performUpload(options: FileStationUploadOptions(conflictPolicy: .skip))
        } else {
            uploadConflict = UploadConflict(names: existing)
        }
    }

    private func performUpload(options: FileStationUploadOptions) {
        let urls = pendingUploadURLs
        pendingUploadURLs.removeAll()
        guard !urls.isEmpty else { return }
        VoiceOver.announce(
            String(localized: "files.progress.uploading"),
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

    /// The stop request goes to the NAS before the tracking is cancelled: interrupting it
    /// first would clear the progress, and with it the identifier of the task to stop.
    private func cancelOperation() {
        guard stopTask == nil else { return }
        VoiceOver.announce(
            String(localized: "files.operation.cancel.announcement"),
            category: .progress,
            priority: .high
        )
        // A transfer runs in this view's own task; a NAS task is stopped through the NAS. The
        // banner shows the same button for both, so it has to reach the right one.
        if vm.isTransferring {
            transferTask?.cancel()
            transferTask = nil
            VoiceOver.announce(
                String(localized: "files.operation.stopped"),
                category: .result,
                priority: .high
            )
            return
        }
        stopTask = Task {
            let outcome = await vm.stopActiveOperation()
            operationTask?.cancel()
            VoiceOver.announce(outcome, priority: .high)
            stopTask = nil
        }
    }

    /// An operation started before leaving the module is still running on the NAS: the
    /// progress banner picks it back up on return.
    private func resumeUnfinishedOperation() {
        guard operationTask == nil else { return }
        operationTask = Task {
            let outcome = await vm.resumeUnfinishedOperation()
            guard !Task.isCancelled, let outcome else {
                operationTask = nil
                return
            }
            VoiceOver.announce(outcome, priority: .high)
            operationTask = nil
        }
    }

    private func suggestedArchiveName(for items: [FileStationItem]) -> String {
        guard items.count == 1, let item = items.first else {
            return String(localized: "files.archive.name.placeholder")
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
            // Keyboard focus goes to the table even with nothing in it, so that pasting works
            // here; the VoiceOver cursor stays on the message above it.
            tableFocusRequestID += 1
        }
        announceSummary(category: .navigation)
    }

    private func restoreInitialContentFocus() {
        if vm.errorMessage != nil {
            focusEmptyState = true
        } else if vm.sortedItems.isEmpty {
            focusEmptyState = true
            tableFocusRequestID += 1
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
