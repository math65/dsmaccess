//
//  DockerProjectCreationSheet.swift
//  dsmaccess
//
//  Creating a compose project. DSM spreads this over a four-step wizard; the app keeps it on
//  one form, where a screen reader can review every field before committing.
//

import SwiftUI
import UniformTypeIdentifiers

struct DockerProjectCreationSheet: View {
    let vm: DockerProjectsViewModel

    @State private var name = ""
    @State private var sharePath = ""
    @State private var content = ""
    @State private var startAfterCreation = true
    @State private var shareInfo: DockerProjectShareInfo?
    @State private var shareNames: [String] = []
    @State private var showsFolderPicker = false
    @State private var showsFileImporter = false
    @State private var fileErrorMessage: String?
    @State private var creationErrorMessage: String?
    @State private var isCreating = false
    @AccessibilityFocusState private var nameFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("common.label.information") {
                    nameField
                    pathField
                }

                if let shareInfo, shareInfo.hasComposeFile {
                    Section {
                        Label(
                            String(
                                localized: "containers.project.create.compose.existing",
                                defaultValue: "This folder already holds \((shareInfo.composePath as NSString).lastPathComponent). Creating the project overwrites it with the text below."
                            ),
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.readableOrange)

                        Button("containers.project.create.compose.reuse") {
                            content = shareInfo.content
                            VoiceOver.announce(
                                String(localized: "containers.project.create.compose.reused"),
                                category: .result
                            )
                        }
                        .disabled(isCreating || shareInfo.content.isEmpty)
                    }
                }

                Section("containers.project.detail.compose") {
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .accessibilityLabel("containers.project.create.compose.label")
                        .disabled(isCreating)

                    Button("containers.project.create.compose.import") {
                        showsFileImporter = true
                    }
                    .disabled(isCreating)
                    .help("containers.project.create.compose.import.hint")

                    if let fileErrorMessage {
                        Text(fileErrorMessage)
                            .foregroundStyle(.readableRed)
                    }
                }

                Section {
                    Toggle("containers.project.create.start_after", isOn: $startAfterCreation)
                        .disabled(isCreating)
                }

                if let creationErrorMessage {
                    Section {
                        Label(creationErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($errorFocused)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("containers.project.create.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.button.cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.button.create") { Task { await create() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate)
                }
                if isCreating {
                    ToolbarItem(placement: .status) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("containers.project.create.in_progress")
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 620)
        .sheet(isPresented: $showsFolderPicker) {
            SharedFolderPickerSheet(
                initialPath: sharePath,
                shareNames: shareNames,
                loadFolders: vm.folders,
                createFolder: { parent, folderName in
                    try await vm.createFolder(in: parent, named: folderName)
                }
            ) { selectedPath in
                sharePath = selectedPath
            }
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            Task { await importCompose(result) }
        }
        .task {
            await Task.yield()
            nameFocused = true
            await loadShareNames()
        }
        .task(id: sharePath) {
            await loadShareInfo()
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("containers.project.create.name", text: $name)
                .accessibilityFocused($nameFocused)
                // Carried on the field as well as written under it: the text below is only
                // met by someone reviewing the form, not by someone typing in it.
                .accessibilityHint(nameProblem ?? String(localized: "containers.project.create.name.rule"))
                .disabled(isCreating)
            if let nameProblem {
                Text(nameProblem)
                    .font(.caption)
                    .foregroundStyle(.readableRed)
            } else {
                Text("containers.project.create.name.rule")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
            }
        }
    }

    private var pathField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("containers.project.create.path", text: $sharePath)
                    .disabled(isCreating)
                Button("containers.project.create.path.browse", systemImage: "folder") {
                    showsFolderPicker = true
                }
                .labelStyle(.iconOnly)
                .disabled(isCreating || shareNames.isEmpty)
                .help("containers.project.create.path.browse.hint")
            }
            Text("containers.project.create.path.rule")
                .font(.caption)
                .foregroundStyle(.readableSecondary)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedPath: String {
        sharePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Written out under the field rather than only disabling the button: a button that is
    /// disabled for an unsaid reason is a dead end for a screen reader.
    private var nameProblem: String? {
        guard !trimmedName.isEmpty else { return nil }
        // Read from the list the view model already holds rather than copied in: a duplicate
        // check against a stale snapshot would be worse than none.
        if vm.projects.contains(where: { $0.name == trimmedName }) {
            return String(localized: "containers.project.create.error.name_taken_short")
        }
        if !DockerProject.isValidName(trimmedName) {
            return String(localized: "containers.project.create.error.invalid_name")
        }
        return nil
    }

    private var canCreate: Bool {
        !isCreating
            && !trimmedName.isEmpty
            && !trimmedPath.isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && nameProblem == nil
    }

    private func loadShareNames() async {
        do {
            shareNames = try await vm.shareNames()
        } catch {
            // Browsing is a convenience: the path can still be typed, so this stays quiet
            // rather than throwing an error at a form the user has not submitted yet.
            guard !DSMError.isCancellation(error) else { return }
            shareNames = []
        }
    }

    private func loadShareInfo() async {
        let path = trimmedPath
        guard !path.isEmpty else {
            shareInfo = nil
            return
        }
        // The path can be typed as well as picked, and this task restarts on every keystroke.
        // Waiting first turns that into one request once typing settles; a restart cancels
        // the wait rather than the NAS's answer.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        do {
            let info = try await vm.shareInfo(path: path)
            guard !Task.isCancelled, trimmedPath == path else { return }
            shareInfo = info
            if info.hasComposeFile {
                // Announced but not focused: the user is most likely still in the path field,
                // and taking focus away mid-entry would be worse than the warning is useful.
                VoiceOver.announce(
                    String(localized: "containers.project.create.compose.existing.announcement"),
                    category: .result,
                    priority: .high
                )
            }
        } catch {
            guard !Task.isCancelled, !DSMError.isCancellation(error), trimmedPath == path else { return }
            shareInfo = nil
        }
    }

    private func importCompose(_ result: Result<[URL], Error>) async {
        fileErrorMessage = nil
        switch result {
        case .failure(let error):
            fileErrorMessage = error.localizedDescription
            VoiceOver.announce(error.localizedDescription, category: .error, priority: .high)
        case .success(let urls):
            guard let url = urls.first else { return }
            let text = await Task.detached { Self.readText(at: url) }.value
            guard let text else {
                fileErrorMessage = String(localized: "containers.project.create.compose.import_failed")
                VoiceOver.announce(fileErrorMessage ?? "", category: .error, priority: .high)
                return
            }
            content = text
            VoiceOver.announce(
                String(
                    localized: "containers.project.create.compose.imported",
                    defaultValue: "Compose file loaded from \(url.lastPathComponent)"
                ),
                category: .result
            )
        }
    }

    /// Read off the main actor, and only as UTF-8: a compose file that is not text is a
    /// mistaken pick, not something to send to the NAS.
    private nonisolated static func readText(at url: URL) -> String? {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if hasSecurityScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func create() async {
        guard canCreate else { return }
        isCreating = true
        creationErrorMessage = nil
        VoiceOver.announce(
            String(localized: "containers.project.create.in_progress"),
            category: .progress
        )
        let (outcome, projectExists) = await vm.create(
            name: trimmedName,
            sharePath: trimmedPath,
            content: content,
            startAfterCreation: startAfterCreation
        )
        isCreating = false
        VoiceOver.announce(outcome, priority: .high)
        // Closing on any created project, even one whose build failed: the form has nothing
        // left to offer, and the build output is waiting in the report sheet.
        guard !projectExists else {
            dismiss()
            return
        }
        if case .failure(let message) = outcome {
            // Nothing was created, so the form stays open with the compose file intact, and
            // the reason stays on screen rather than only passing through VoiceOver.
            creationErrorMessage = message
            errorFocused = true
        }
    }
}
