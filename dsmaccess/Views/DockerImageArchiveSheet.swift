//
//  DockerImageArchiveSheet.swift
//  dsmaccess
//
//  Choosing where an image archive goes, or which one comes back in. DSM browses its own file
//  chooser here; the app reuses the shared-folder picker and then lists the archives it finds,
//  so nothing has to be typed from memory.
//

import SwiftUI

struct DockerImageArchiveSheet: View {
    enum Mode {
        /// Writing the image out. Only a folder is chosen; DSM names the archive itself.
        case export(DockerImage)
        /// Reading an archive back in. A folder, then one of the archives inside it.
        case importArchive
    }

    let mode: Mode
    let vm: DockerImagesViewModel

    @State private var folderPath = "/docker"
    @State private var shareNames: [String] = []
    @State private var archives: [FileStationItem] = []
    @State private var selectedArchive: String?
    @State private var isLoadingArchives = false
    @State private var showsFolderPicker = false
    @State private var errorMessage: String?
    @State private var archiveGeneration = 0
    @AccessibilityFocusState private var focusFolder: Bool
    @AccessibilityFocusState private var focusError: Bool
    @Environment(\.dismiss) private var dismiss

    private var isExporting: Bool {
        if case .export = mode { return true }
        return false
    }

    private var image: DockerImage? {
        if case .export(let image) = mode { return image }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("containers.image.archive.folder") {
                    LabeledContent("containers.image.archive.folder", value: folderPath)
                        .labeledContentStyle(.readable)
                        .accessibilityFocused($focusFolder)
                    Button("common.folder_picker.choose") { showsFolderPicker = true }
                        .disabled(vm.isTransferring)
                }

                if isExporting {
                    if let image {
                        Section("containers.image.archive.result") {
                            // DSM decides the file name, so showing it is the only way the user
                            // knows what to look for afterwards.
                            LabeledContent(
                                "containers.image.archive.file",
                                value: image.exportArchiveName(tag: image.tags.first ?? "latest")
                            )
                            .labeledContentStyle(.readable)
                        }
                    }
                } else {
                    Section("containers.image.archive.available") {
                        if isLoadingArchives {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("containers.image.archive.loading")
                                    .foregroundStyle(.readableSecondary)
                            }
                        } else if archives.isEmpty {
                            Text("containers.image.archive.none")
                                .foregroundStyle(.readableSecondary)
                        } else {
                            Picker("containers.image.archive.file", selection: $selectedArchive) {
                                ForEach(archives, id: \.name) { archive in
                                    Text(archive.name).tag(String?.some(archive.name))
                                }
                            }
                            .disabled(vm.isTransferring)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($focusError)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel(isExporting
                                ? String(localized: "containers.image.action.export")
                                : String(localized: "containers.image.import.from_nas"))
            .navigationTitle(isExporting
                             ? "containers.image.action.export"
                             : "containers.image.import.from_nas")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.button.cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(vm.isTransferring)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isExporting ? "containers.image.action.export" : "containers.image.action.import") {
                        Task { await run() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRun)
                }
                if vm.isTransferring {
                    ToolbarItem(placement: .status) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(vm.transferDescription
                                                ?? String(localized: "containers.image.archive.working"))
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .sheet(isPresented: $showsFolderPicker) {
            SharedFolderPickerSheet(
                initialPath: folderPath,
                shareNames: shareNames,
                loadFolders: vm.folders,
                createFolder: nil
            ) { chosen in
                folderPath = chosen
            }
        }
        .task {
            shareNames = (try? await vm.shareNames()) ?? []
            await loadArchives()
            await Task.yield()
            focusFolder = true
        }
        .onChange(of: folderPath) { _, _ in
            Task { await loadArchives() }
        }
    }

    private var canRun: Bool {
        guard !vm.isTransferring, !folderPath.isEmpty else { return false }
        return isExporting || selectedArchive != nil
    }

    /// Reloads the archives of the chosen folder. A slower answer for a folder the user has
    /// already left must not replace the list they are looking at.
    private func loadArchives() async {
        guard !isExporting else { return }
        archiveGeneration += 1
        let generation = archiveGeneration
        isLoadingArchives = true
        selectedArchive = nil
        defer { if generation == archiveGeneration { isLoadingArchives = false } }

        do {
            let found = try await vm.archives(in: folderPath)
            guard generation == archiveGeneration else { return }
            archives = found
            selectedArchive = found.first?.name
        } catch {
            guard generation == archiveGeneration, !DSMError.isCancellation(error) else { return }
            archives = []
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func run() async {
        guard canRun else { return }
        errorMessage = nil

        let outcome: DSMOperationOutcome
        if let image {
            VoiceOver.announce(
                String(
                    localized: "containers.image.export.in_progress",
                    defaultValue: "Exporting \(image.displayName)"
                ),
                category: .progress
            )
            outcome = await vm.export(
                image,
                tag: image.tags.first ?? "latest",
                to: folderPath
            )
        } else {
            guard let selectedArchive else { return }
            VoiceOver.announce(
                String(localized: "containers.image.import.in_progress"),
                category: .progress
            )
            outcome = await vm.importImage(at: "\(folderPath)/\(selectedArchive)")
        }

        VoiceOver.announce(outcome, priority: .high)
        switch outcome {
        case .success:
            dismiss()
        case .failure(let message):
            errorMessage = message
            focusError = true
        case .cancelled:
            break
        }
    }
}
