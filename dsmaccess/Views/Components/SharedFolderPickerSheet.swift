//
//  SharedFolderPickerSheet.swift
//  dsmaccess
//
//  Picks a folder inside the shared folders of the NAS. Used wherever a screen needs a
//  destination on the server rather than on the Mac. Browsing works like the File Station
//  module: the root lists the shared folders themselves, and the table underneath carries
//  the Finder-style keyboard handling.
//

import SwiftUI

struct SharedFolderPickerSheet: View {
    /// Names of the shared folders that can be browsed, without their leading slash.
    let shareNames: [String]
    let loadFolders: (String) async throws -> [FileStationItem]
    /// Creating a folder in the browsed one. Passing nil leaves the button out, for callers
    /// that only ever pick among folders that already exist.
    let createFolder: ((String, String) async throws -> Void)?
    let onChoose: (String) -> Void

    /// Empty while the picker is at its root, where the shared folders themselves are listed.
    @State private var currentPath: String
    @State private var folders: [FolderPickerRow] = []
    @State private var selection: String?
    @State private var tableFocusRequestID = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var reloadCount = 0
    @State private var showsNameEntry = false
    @AccessibilityFocusState private var headingFocused: Bool
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        initialPath: String,
        shareNames: [String],
        loadFolders: @escaping (String) async throws -> [FileStationItem],
        createFolder: ((String, String) async throws -> Void)? = nil,
        onChoose: @escaping (String) -> Void
    ) {
        self.shareNames = shareNames
        self.loadFolders = loadFolders
        self.createFolder = createFolder
        self.onChoose = onChoose
        // Reopening where the caller already points feels like coming back; anything else
        // starts at the root, on the list of shares.
        let roots = shareNames.map { "/\($0)" }
        let isInsideAShare = roots.contains {
            initialPath == $0 || initialPath.hasPrefix($0 + "/")
        }
        _currentPath = State(initialValue: isInsideAShare ? initialPath : "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("common.folder_picker.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .padding()

            Form {
                LabeledContent("common.column.path") {
                    Text(verbatim: currentPath.isEmpty
                        ? String(localized: "common.folder_picker.root.label")
                        : currentPath)
                        .textSelection(.enabled)
                }
                .labeledContentStyle(.readable)

                HStack {
                    Button("common.button.parent_folder", systemImage: "chevron.up", action: goUp)
                        .disabled(currentPath.isEmpty || isLoading)
                    Button("common.button.refresh", systemImage: "arrow.clockwise") {
                        reloadCount += 1
                    }
                    .disabled(isLoading)
                    if createFolder != nil {
                        Button("common.button.new_folder", systemImage: "folder.badge.plus") {
                            showsNameEntry = true
                        }
                        .disabled(currentPath.isEmpty || isLoading)
                        .help("common.folder_picker.new_folder.hint")
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("common.folder_picker.location.label")
            .frame(maxHeight: 140)

            Divider()
            content

            Divider()
            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("common.folder_picker.choose.action") {
                    onChoose(currentPath)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(currentPath.isEmpty || isLoading)
            }
            .padding()
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
        .onAppear {
            headingFocused = true
            VoiceOver.announce(String(localized: "common.folder_picker.title"), category: .navigation)
        }
    }

    @ViewBuilder
    private var content: some View {
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
        guard let createFolder, !currentPath.isEmpty else { return }
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
}
