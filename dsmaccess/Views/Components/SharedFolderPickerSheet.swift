//
//  SharedFolderPickerSheet.swift
//  dsmaccess
//
//  Picks a folder inside the shared folders of the NAS. Used wherever a screen needs a
//  destination on the server rather than on the Mac.
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

    @State private var currentPath: String
    @State private var folders: [FileStationItem] = []
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
        let roots = shareNames.map { "/\($0)" }
        let initialRoot = roots.first {
            initialPath == $0 || initialPath.hasPrefix($0 + "/")
        }
        _currentPath = State(initialValue: initialRoot == nil ? (roots.first ?? "") : initialPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("common.folder_picker.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .padding()

            Form {
                Picker("common.folder_picker.title", selection: rootBinding) {
                    ForEach(shareRoots, id: \.self) { root in
                        Text(verbatim: root).tag(root)
                    }
                }
                .disabled(shareRoots.count < 2)

                LabeledContent("common.column.path") {
                    Text(verbatim: currentPath)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("common.button.parent_folder", systemImage: "chevron.up", action: goUp)
                        .disabled(!canGoUp || isLoading)
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
            .frame(maxHeight: 180)

            Divider()
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
            } else if folders.isEmpty {
                ContentUnavailableView("common.empty.folder.description", systemImage: "folder")
                    .accessibilityFocused($contentFocused)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(folders) { folder in
                            Button {
                                currentPath = folder.path
                            } label: {
                                Label(folder.name, systemImage: "folder")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("common.folder_picker.open.hint")

                            Divider()
                        }
                    }
                }
                .accessibilityLabel(folderCountAnnouncement)
                .accessibilityFocused($contentFocused)
            }

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

    /// Reloading is keyed on the browsed path plus a counter, so refreshing and creating a
    /// folder reload the same path instead of being swallowed as an unchanged identity.
    private var reloadKey: String {
        "\(reloadCount)\u{1F}\(currentPath)"
    }

    private var shareRoots: [String] {
        shareNames.map { "/\($0)" }
    }

    private var currentRoot: String {
        shareRoots.first { currentPath == $0 || currentPath.hasPrefix($0 + "/") }
            ?? shareRoots.first
            ?? ""
    }

    private var rootBinding: Binding<String> {
        Binding(
            get: { currentRoot },
            set: { currentPath = $0 }
        )
    }

    private var canGoUp: Bool {
        !currentPath.isEmpty && currentPath != currentRoot
    }

    private func goUp() {
        guard canGoUp else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        currentPath = parent.count >= currentRoot.count ? parent : currentRoot
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
            folders = []
            return
        }
        isLoading = true
        errorMessage = nil
        contentFocused = true
        VoiceOver.announce(String(localized: "common.status.loading"), category: .progress)
        defer {
            if currentPath == requestedPath {
                isLoading = false
            }
        }
        do {
            let loadedFolders = try await loadFolders(requestedPath)
            guard !Task.isCancelled, currentPath == requestedPath else { return }
            folders = loadedFolders
            contentFocused = true
            VoiceOver.announce(folderCountAnnouncement, category: .result)
        } catch {
            guard !Task.isCancelled, !DSMError.isCancellation(error), currentPath == requestedPath else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            errorFocused = true
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }

    private var folderCountAnnouncement: String {
        folders.count == 1
            ? String(localized: "common.folder_picker.count_one")
            : String(localized: "common.folder_picker.count", defaultValue: "\(folders.count) folders available")
    }
}
