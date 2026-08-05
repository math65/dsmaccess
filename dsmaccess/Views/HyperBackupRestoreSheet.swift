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
    @State private var order = [KeyPathComparator(\HyperBackupEntry.sortableKind, order: .forward)]
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
                VoiceOver.announce(outcome, priority: .high)
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
        } else if viewModel.entries.isEmpty {
            EmptyModuleView(
                title: "hyper_backup.restore.empty.title",
                systemImage: "folder",
                description: "hyper_backup.restore.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else {
            Table(
                viewModel.entries.sorted(using: order),
                selection: $selection,
                sortOrder: $order
            ) {
                TableColumn("common.column.name", value: \.name) { entry in
                    Text(entry.name)
                }
                TableColumn("hyper_backup.restore.column.kind", value: \.sortableKind) { entry in
                    Text(entry.kindDescription)
                }
                TableColumn("common.column.size", value: \.sortableSize) { entry in
                    Text(entry.sizeDescription)
                }
                TableColumn("hyper_backup.restore.column.modified", value: \.sortableModification) { entry in
                    Text(entry.modificationDescription)
                }
                TableColumn("hyper_backup.restore.column.condition", value: \.sortableCondition) { entry in
                    Text(entry.conditionDescription)
                }
            }
            .accessibilityLabel("hyper_backup.restore.table.label")
            .accessibilityFocused($focusContent)
            .contextMenu(forSelectionType: String.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                if let entry = singleFolder(in: ids) {
                    Task { await open(entry) }
                }
            }
        }
    }

    /// The same entries in the same order whatever the selection holds, so the menu never
    /// changes shape from one row to the next.
    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        Button("hyper_backup.restore.open.button") {
            if let entry = singleFolder(in: ids) {
                Task { await open(entry) }
            }
        }
        .disabled(singleFolder(in: ids) == nil)

        Button("hyper_backup.restore.copy_to.button") {
            Task { await prepareRestore(of: entries(for: ids)) }
        }
        .disabled(ids.isEmpty || viewModel.isRestoring)

        Button("hyper_backup.restore.in_place.button") {
            pendingInPlaceRestore = HyperBackupPendingRestore(entries: entries(for: ids))
        }
        .disabled(ids.isEmpty || viewModel.isRestoring)

        Button("hyper_backup.restore.download.button") {
            if let file = singleFile(in: ids) {
                Task { await download(file) }
            }
        }
        .disabled(singleFile(in: ids) == nil || viewModel.isDownloading)

        Divider()

        Button("hyper_backup.restore.go_up.button") {
            Task { await goUp() }
        }
        .disabled(viewModel.isAtRoot)

        Button("hyper_backup.restore.go_to_root.button") {
            Task { await goToRoot() }
        }
        .disabled(viewModel.isAtRoot)
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
    /// `source_path` carries a single path here rather than a list.
    private func singleFile(in ids: Set<String>) -> HyperBackupEntry? {
        let matches = entries(for: ids)
        guard matches.count == 1, let entry = matches.first, !entry.isFolder else { return nil }
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
            await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .result : .error
        )
    }

    private func open(_ entry: HyperBackupEntry) async {
        selection = []
        await viewModel.open(entry)
        focusContent = true
        VoiceOver.announce(viewModel.summary, category: .result)
    }

    private func goUp() async {
        selection = []
        await viewModel.goUp()
        focusContent = true
        VoiceOver.announce(viewModel.summary, category: .result)
    }

    /// Climbing one folder at a time is tedious deep in a backup, so the whole way back is
    /// one command.
    private func goToRoot() async {
        selection = []
        await viewModel.goToRoot()
        focusContent = true
        VoiceOver.announce(viewModel.summary, category: .result)
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
        VoiceOver.announce(outcome, priority: .high)
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
        VoiceOver.announce(outcome, priority: .high)
    }

    private func prepareRestore(of entries: [HyperBackupEntry]) async {
        guard !entries.isEmpty else { return }
        await viewModel.loadDestinations()
        guard !viewModel.destinations.isEmpty else {
            VoiceOver.announce(
                String(localized: "hyper_backup.restore.error.no_destination"),
                category: .error,
                priority: .high
            )
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
