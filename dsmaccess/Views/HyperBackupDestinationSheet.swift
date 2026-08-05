//
//  HyperBackupDestinationSheet.swift
//  dsmaccess
//
//  Choosing where a restore puts its copy, and whether it may replace anything. The sheet
//  is the folder browser itself: the destination is the folder being browsed, stated in
//  clear text next to the options, with no separate picking step.
//

import SwiftUI

struct HyperBackupDestinationSheet: View {
    let entries: [HyperBackupEntry]
    let shareNames: [String]
    let isRestoring: Bool
    let loadFolders: (String) async throws -> [FileStationItem]
    let createFolder: (String, String) async throws -> Void
    /// Returns whether the restore succeeded, so the sheet only closes on success and an
    /// error stays readable where it happened.
    let restore: (String, Bool) async -> Bool

    /// Empty while the browser is at its root, where the shared folders themselves are
    /// listed and there is no destination to restore to yet.
    @State private var currentPath = ""
    @State private var folders: [FolderPickerRow] = []
    @State private var selection: String?
    @State private var tableFocusRequestID = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reloadCount = 0
    @State private var showsNameEntry = false
    @State private var replacesExisting = false
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                browser
                Divider()
                options
            }
            .navigationTitle("hyper_backup.restore.destination.title")
            .toolbar { toolbar }
        }
        .frame(minWidth: 620, minHeight: 560)
        .sheet(isPresented: $showsNameEntry) {
            NameEntrySheet(
                title: "common.button.new_folder",
                fieldLabel: "common.column.name",
                confirmLabel: "common.button.create",
                announcement: String(localized: "common.folder_picker.new_folder.announcement")
            ) { name in
                Task { await create(named: name) }
            }
        }
        .task(id: reloadKey) {
            await loadCurrentFolder()
        }
    }

    @ViewBuilder
    private var browser: some View {
        if isLoading {
            ProgressView("common.status.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityFocused($contentFocused)
        } else if let errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.readableRed)
                    .accessibilityFocused($errorFocused)
                Button("common.button.retry") { reloadCount += 1 }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()
        } else {
            FolderPickerTableView(
                rows: folders,
                selection: $selection,
                focusRequestID: tableFocusRequestID,
                onOpen: { open($0) },
                onGoUp: goUp
            )
            // The empty state covers the table instead of replacing it: replacing it would
            // take the table's keyboard handling down with it, and ⌘↑ no longer led back
            // out of an empty folder.
            .overlay {
                if folders.isEmpty {
                    ContentUnavailableView("common.empty.folder.description", systemImage: "folder")
                        .background(.background)
                        .accessibilityFocused($contentFocused)
                        // The message is there to be read, not clicked: swallowing mouse
                        // events would keep the table underneath from taking keyboard focus.
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// What will happen, stated where the decision is made: the destination follows the
    /// browsing, the toggle decides the fate of what is already there.
    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(restorationStatement)
            Toggle("hyper_backup.restore.replace.label", isOn: $replacesExisting)
                .accessibilityHint("hyper_backup.restore.replace.hint")
            if let consequence {
                Text(consequence)
                    .font(.caption)
                    .foregroundStyle(replacesExisting ? .readableOrange : .readableSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("common.button.parent_folder", systemImage: "chevron.up", action: goUp)
                .disabled(currentPath.isEmpty || isLoading)
        }

        ToolbarItem {
            Button("common.button.new_folder", systemImage: "folder.badge.plus") {
                showsNameEntry = true
            }
            .disabled(currentPath.isEmpty || isLoading)
            .help("common.folder_picker.new_folder.hint")
        }

        ToolbarItem {
            Button("common.button.refresh", systemImage: "arrow.clockwise") {
                reloadCount += 1
            }
            .disabled(isLoading)
        }

        ToolbarItem(placement: .cancellationAction) {
            Button("common.button.cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("hyper_backup.restore.restore.button") {
                Task { await submit() }
            }
            .disabled(currentPath.isEmpty || isLoading || isRestoring)
        }
    }

    /// Names what goes where before anything is clicked. At the root there is no
    /// destination yet, so the line says what to do instead.
    private var restorationStatement: String {
        guard !currentPath.isEmpty else {
            return String(localized: "hyper_backup.restore.consequence.none")
        }
        guard let single = entries.first, entries.count == 1 else {
            return String(localized: "hyper_backup.restore.destination.statement.several", defaultValue: "\(entries.count) items will be restored to \(currentPath)")
        }
        return String(localized: "hyper_backup.restore.destination.statement.one", defaultValue: "\(single.name) will be restored to \(currentPath)")
    }

    /// States the outcome plainly in both directions: the safe one is the default, and the
    /// destructive one names what it costs rather than only warning in colour.
    private var consequence: String? {
        guard !currentPath.isEmpty else { return nil }
        return replacesExisting
            ? String(localized: "hyper_backup.restore.consequence.replace", defaultValue: "Items of the same name already in \(currentPath) will be replaced, and their current contents cannot be recovered.")
            : String(localized: "hyper_backup.restore.consequence.keep", defaultValue: "The originals are left untouched. If \(currentPath) already holds items of the same name, nothing is restored and the app says so.")
    }

    /// Reloading is keyed on the browsed path plus a counter, so refreshing and creating a
    /// folder reload the same path instead of being swallowed as an unchanged identity.
    private var reloadKey: String {
        "\(reloadCount)\u{1F}\(currentPath)"
    }

    private func open(_ folder: FolderPickerRow) {
        selection = nil
        currentPath = folder.path
    }

    private func goUp() {
        guard !currentPath.isEmpty else { return }
        selection = nil
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent == "/" ? "" : parent
    }

    private func create(named name: String) async {
        guard !currentPath.isEmpty else { return }
        let parent = currentPath
        do {
            try await createFolder(parent, name)
            guard !Task.isCancelled else { return }
            VoiceOver.announce(
                String(
                    localized: "common.folder_picker.new_folder.success",
                    defaultValue: "Folder created: \(name)"
                ),
                category: .result,
                priority: .high
            )
            reloadCount += 1
        } catch {
            guard !Task.isCancelled, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            errorFocused = true
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }

    private func loadCurrentFolder() async {
        let requestedPath = currentPath
        guard !requestedPath.isEmpty else {
            // The root needs no network round trip: the shares were handed in by the caller.
            folders = shareNames.map { FolderPickerRow(name: $0, path: "/\($0)") }
            errorMessage = nil
            settleAfterNavigation()
            return
        }
        isLoading = true
        errorMessage = nil
        VoiceOver.announce(String(localized: "common.status.loading"), category: .progress)
        defer {
            if currentPath == requestedPath {
                isLoading = false
            }
        }
        do {
            let loadedFolders = try await loadFolders(requestedPath)
            guard !Task.isCancelled, currentPath == requestedPath else { return }
            folders = loadedFolders.map { FolderPickerRow(name: $0.name, path: $0.path) }
            settleAfterNavigation()
        } catch {
            guard !Task.isCancelled, !DSMError.isCancellation(error), currentPath == requestedPath else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            errorFocused = true
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }

    /// Selection and keyboard focus land on the first row of the folder just entered, the
    /// way the File Station browser settles after navigating.
    private func settleAfterNavigation() {
        if let first = folders.first {
            selection = first.path
            tableFocusRequestID += 1
        } else {
            selection = nil
            contentFocused = true
            // Keyboard focus goes to the table even with nothing in it, so ⌘↑ still leads
            // back out; the VoiceOver cursor stays on the message above it.
            tableFocusRequestID += 1
        }
        VoiceOver.announce(folderCountAnnouncement, category: .result)
    }

    private var folderCountAnnouncement: String {
        folders.count == 1
            ? String(localized: "common.folder_picker.count_one")
            : String(localized: "common.folder_picker.count", defaultValue: "\(folders.count) folders available")
    }

    private func submit() async {
        guard !currentPath.isEmpty else { return }
        if await restore(currentPath, replacesExisting) {
            dismiss()
        }
    }
}
