//
//  USBCopyFolderPickerSheet.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyFolderPickerSheet: View {
    let shares: [SharedFolder]
    let loadFolders: (String) async throws -> [FileStationItem]
    let onChoose: (String) -> Void

    @State private var currentPath: String
    @State private var folders: [FileStationItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var headingFocused: Bool
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        initialPath: String,
        shares: [SharedFolder],
        loadFolders: @escaping (String) async throws -> [FileStationItem],
        onChoose: @escaping (String) -> Void
    ) {
        self.shares = shares
        self.loadFolders = loadFolders
        self.onChoose = onChoose
        let roots = shares.map { "/\($0.name)" }
        let initialRoot = roots.first {
            initialPath == $0 || initialPath.hasPrefix($0 + "/")
        }
        _currentPath = State(initialValue: initialRoot == nil ? (roots.first ?? "") : initialPath)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("usb_copy.folder_picker.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .padding()

            Form {
                Picker("usb_copy.folder_picker.title", selection: rootBinding) {
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
                        Task { await loadCurrentFolder() }
                    }
                    .disabled(isLoading)
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
                    Button("common.button.retry") { Task { await loadCurrentFolder() } }
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
                            .accessibilityHint("usb_copy.folder_picker.open.hint")

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
                Button("usb_copy.folder_picker.choose.action") {
                    onChoose(currentPath)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(currentPath.isEmpty || isLoading)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 560)
        .task(id: currentPath) {
            await loadCurrentFolder()
        }
        .onAppear {
            headingFocused = true
            VoiceOver.announce(String(localized: "usb_copy.folder_picker.title"), category: .navigation)
        }
    }

    private var shareRoots: [String] {
        shares.map { "/\($0.name)" }
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
            VoiceOver.announce(
                loadedFolders.count == 1
                    ? String(localized: "usb_copy.folder_picker.count_one")
                    : String(localized: "usb_copy.folder_picker.count", defaultValue: "\(loadedFolders.count) folders available"),
                category: .result
            )
        } catch {
            guard !Task.isCancelled, !DSMError.isCancellation(error), currentPath == requestedPath else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            errorFocused = true
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }

    private var folderCountAnnouncement: String {
        folders.count == 1
            ? String(localized: "usb_copy.folder_picker.count_one")
            : String(localized: "usb_copy.folder_picker.count", defaultValue: "\(folders.count) folders available")
    }
}
