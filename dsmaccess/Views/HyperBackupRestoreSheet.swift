//
//  HyperBackupRestoreSheet.swift
//  dsmaccess
//
//  Browsing a backup version and putting what it holds back somewhere safe.
//

import AppKit
import SwiftUI

struct HyperBackupRestoreSheet: View {
    @State private var viewModel: HyperBackupRestoreViewModel
    @State private var selection: Set<String> = []
    @State private var tableFocusRequestID = 0
    @State private var pendingRestore: HyperBackupPendingRestore?
    @State private var pendingInPlaceRestore: HyperBackupPendingRestore?
    @AccessibilityFocusState private var focusContent: Bool
    @Environment(\.dismiss) private var dismiss

    init(task: HyperBackupTask, version: HyperBackupVersion, session: SessionStore) {
        _viewModel = State(
            initialValue: HyperBackupRestoreViewModel(
                task: task,
                version: version,
                session: session
            )
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) { statusBar }
        }
        .frame(minWidth: 720, minHeight: 560)
        .task { await load(restoresInitialFocus: true) }
        .sheet(item: $pendingRestore) { restore in
            HyperBackupDestinationSheet(
                entries: restore.entries,
                shareNames: viewModel.shareNames,
                isRestoring: viewModel.isRestoring,
                loadFolders: viewModel.folders,
                createFolder: viewModel.createFolder
            ) { destinationPath, overwriting in
                let outcome = await viewModel.restore(
                    restore.entries,
                    to: destinationPath,
                    overwriting: overwriting
                )
                OperationFailures.shared.present(outcome, from: .hyperBackup)
                if case .success = outcome { return true }
                return false
            }
        }
        .confirmationDialog(
            "hyper_backup.restore.in_place.confirm",
            isPresented: Binding(
                get: { pendingInPlaceRestore != nil },
                set: { if !$0 { pendingInPlaceRestore = nil } }
            ),
            presenting: pendingInPlaceRestore
        ) { pending in
            Button(String(localized: "hyper_backup.restore.in_place.action", defaultValue: "Replace \(describe(pending.entries))"), role: .destructive) {
                Task { await restoreInPlace(pending.entries) }
            }
            Button("common.button.cancel", role: .cancel) { }
        } message: { pending in
            Text(inPlaceWarning(for: pending.entries))
        }
    }

    private var title: String {
        guard let completion = viewModel.version.completionDate else {
            return viewModel.task.name
        }
        return String(localized: "hyper_backup.restore.title", defaultValue: "\(viewModel.task.name) — backup of \(completion.formatted(date: .abbreviated, time: .shortened))")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.entries.isEmpty {
            ModuleLoadingView("hyper_backup.restore.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage = viewModel.errorMessage, viewModel.entries.isEmpty {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($focusContent)
        } else {
            HyperBackupEntryTableView(
                entries: viewModel.sortedEntries,
                selection: $selection,
                focusRequestID: tableFocusRequestID,
                isRestoring: viewModel.isRestoring,
                isDownloading: viewModel.isDownloading,
                isAtRoot: viewModel.isAtRoot,
                onOpen: { entry in Task { await open(entry) } },
                onRestoreCopy: { entries in Task { await prepareRestore(of: entries) } },
                onRestoreInPlace: { pendingInPlaceRestore = HyperBackupPendingRestore(entries: $0) },
                onDownload: { entry in Task { await download(entry) } },
                onGoUp: { Task { await goUp() } },
                onGoToRoot: { Task { await goToRoot() } }
            )
            // The empty state covers the table instead of replacing it: replacing it would
            // take the table's keyboard handling down with it, and ⌘↑ no longer led back
            // out of an empty backup folder.
            .overlay {
                if viewModel.entries.isEmpty {
                    EmptyModuleView(
                        title: "hyper_backup.restore.empty.title",
                        systemImage: "folder",
                        description: "hyper_backup.restore.empty.description"
                    )
                    .background(.background)
                    .accessibilityFocused($focusContent)
                    // The message is there to be read, not clicked: swallowing mouse events
                    // would keep the table underneath from ever taking keyboard focus.
                    .allowsHitTesting(false)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button("hyper_backup.restore.go_up.button", systemImage: "arrow.up.left") {
                Task { await goUp() }
            }
            .disabled(viewModel.isAtRoot)
            .help("hyper_backup.restore.go_up.hint")
        }

        ToolbarItem {
            Button("hyper_backup.restore.open.button", systemImage: "folder") {
                if let entry = singleFolder(in: selection) {
                    Task { await open(entry) }
                }
            }
            .disabled(singleFolder(in: selection) == nil)
            .help("hyper_backup.restore.open.hint")
        }

        ToolbarItem {
            Button("hyper_backup.restore.copy_to.button", systemImage: "square.and.arrow.down") {
                Task { await prepareRestore(of: entries(for: selection)) }
            }
            .disabled(selection.isEmpty || viewModel.isRestoring)
            .help("hyper_backup.restore.copy_to.hint")
        }

        ToolbarItem {
            Button("hyper_backup.restore.in_place.button", systemImage: "arrow.uturn.backward") {
                pendingInPlaceRestore = HyperBackupPendingRestore(entries: entries(for: selection))
            }
            .disabled(selection.isEmpty || viewModel.isRestoring)
            .help("hyper_backup.restore.in_place.hint")
        }

        ToolbarItem {
            Button("hyper_backup.restore.download.button", systemImage: "arrow.down.circle") {
                if let file = singleFile(in: selection) {
                    Task { await download(file) }
                }
            }
            .disabled(singleFile(in: selection) == nil || viewModel.isDownloading)
            .help("hyper_backup.restore.download.hint")
        }

        ToolbarItem {
            Menu("hyper_backup.restore.sort.menu.label", systemImage: "arrow.up.arrow.down") {
                ForEach(HyperBackupRestoreViewModel.SortMode.allCases) { mode in
                    Button {
                        viewModel.sortMode = mode
                    } label: {
                        if viewModel.sortMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                    .help(String(localized: "hyper_backup.restore.sort.by", defaultValue: "Sort by \(mode.title)"))
                }
                Divider()
                Button(
                    viewModel.sortAscending ? "hyper_backup.restore.sort.descending.label" : "common.sort.ascending",
                    systemImage: viewModel.sortAscending ? "arrow.down" : "arrow.up"
                ) {
                    viewModel.sortAscending.toggle()
                }
                .help(viewModel.sortAscending ? "hyper_backup.restore.sort.switch_descending.hint" : "hyper_backup.restore.sort.switch_ascending.hint")
            }
            .help("hyper_backup.restore.sort.menu.hint")
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("common.button.close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.summary)
            Spacer()
            if viewModel.isRestoring {
                Text("hyper_backup.restore.in_progress")
            }
            if viewModel.isDownloading {
                Text(downloadStatus)
            }
        }
        .font(.caption)
        .foregroundStyle(.readableSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    /// Bytes rather than a percentage: the server sends no total for a backed-up file, so a
    /// share of the whole would be invented.
    private var downloadStatus: String {
        guard let received = viewModel.downloadProgress?.completedBytes, received > 0 else {
            return String(localized: "hyper_backup.restore.download.in_progress")
        }
        return String(localized: "hyper_backup.restore.download.received", defaultValue: "Downloading, \(received.formatted(.byteCount(style: .file))) received")
    }

    private func entries(for ids: Set<String>) -> [HyperBackupEntry] {
        viewModel.entries.filter { ids.contains($0.id) }
    }

    /// Opening only means something for a single folder: several rows, or one file, have
    /// nowhere to go.
    private func singleFolder(in ids: Set<String>) -> HyperBackupEntry? {
        let matches = entries(for: ids)
        guard matches.count == 1, let entry = matches.first, entry.isFolder else { return nil }
        return entry
    }

    /// DSM downloads one file at a time and leaves the command disabled on a folder, because
    /// `source_path` carries a single path here rather than a list — and on a damaged file,
    /// which its own explorer refuses to hand over either.
    private func singleFile(in ids: Set<String>) -> HyperBackupEntry? {
        let matches = entries(for: ids)
        guard matches.count == 1, let entry = matches.first,
              !entry.isFolder, !entry.isDamaged else { return nil }
        return entry
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "hyper_backup.restore.loading"),
            category: .progress,
            priority: .low
        )
        await viewModel.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { restoreInitialContentFocus() }
        }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .result : .error
        )
    }

    private func restoreInitialContentFocus() {
        if viewModel.errorMessage != nil {
            focusContent = true
        } else if let first = viewModel.sortedEntries.first {
            selection = [first.id]
            tableFocusRequestID += 1
        } else {
            focusContent = true
            tableFocusRequestID += 1
        }
    }

    private func open(_ entry: HyperBackupEntry) async {
        selection = []
        await viewModel.open(entry)
        settleAfterNavigation()
    }

    private func goUp() async {
        selection = []
        await viewModel.goUp()
        settleAfterNavigation()
    }

    /// Climbing one folder at a time is tedious deep in a backup, so the whole way back is
    /// one command.
    private func goToRoot() async {
        selection = []
        await viewModel.goToRoot()
        settleAfterNavigation()
    }

    /// Selection and keyboard focus land on the first row of the folder just entered, the
    /// way the File Station browser settles after navigating.
    private func settleAfterNavigation() {
        if viewModel.errorMessage != nil {
            selection.removeAll()
            focusContent = true
        } else if let first = viewModel.sortedEntries.first {
            selection = [first.id]
            tableFocusRequestID += 1
        } else {
            selection.removeAll()
            focusContent = true
            // Keyboard focus goes to the table even with nothing in it, so ⌘↑ still leads
            // back out; the VoiceOver cursor stays on the message above it.
            tableFocusRequestID += 1
        }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .navigation : .error
        )
    }

    /// Names what the confirmation is about to overwrite. A long selection cannot be listed
    /// in a button, so it falls back to a count.
    private func describe(_ entries: [HyperBackupEntry]) -> String {
        guard let single = entries.first, entries.count == 1 else {
            return String(localized: "hyper_backup.restore.in_place.selection_count", defaultValue: "\(entries.count) items")
        }
        return single.name
    }

    /// DSM only says the restore "will replace your original files" without naming them or
    /// where they are. Both are known here, so both are said.
    private func inPlaceWarning(for entries: [HyperBackupEntry]) -> String {
        String(localized: "hyper_backup.restore.in_place.warning", defaultValue: "\(describe(entries)) will be put back where it came from, in \(viewModel.originDescription), replacing what is there now. The current contents cannot be recovered afterwards.")
    }

    /// The confirmation closes as soon as it is accepted, so without this first announcement
    /// a restore long enough to be felt would run in silence.
    private func restoreInPlace(_ entries: [HyperBackupEntry]) async {
        VoiceOver.announce(
            String(localized: "hyper_backup.restore.in_place.started", defaultValue: "Restoring \(describe(entries)) to its original location"),
            category: .progress
        )
        let outcome = await viewModel.restoreInPlace(entries)
        OperationFailures.shared.present(outcome, from: .hyperBackup)
    }

    /// The save panel is where the user names the file and picks the folder, so the app never
    /// invents a destination on the Mac.
    private func download(_ entry: HyperBackupEntry) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        VoiceOver.announce(
            String(localized: "hyper_backup.restore.download.started", defaultValue: "Downloading \(entry.name)"),
            category: .progress
        )
        let outcome = await viewModel.download(entry, to: url)
        OperationFailures.shared.present(outcome, from: .hyperBackup)
    }

    private func prepareRestore(of entries: [HyperBackupEntry]) async {
        guard !entries.isEmpty else { return }
        await viewModel.loadDestinations()
        guard !viewModel.destinations.isEmpty else {
            OperationFailures.shared.record(OperationFailure(
                message: String(localized: "hyper_backup.restore.error.no_destination"),
                module: .hyperBackup
            ))
            return
        }
        pendingRestore = HyperBackupPendingRestore(entries: entries)
    }
}

/// Carries what is being restored into the sheet, so the sheet never draws against a
/// selection that has moved on since it was asked for.
struct HyperBackupPendingRestore: Identifiable {
    let entries: [HyperBackupEntry]

    var id: String { entries.map(\.path).joined(separator: "\u{1F}") }
}
