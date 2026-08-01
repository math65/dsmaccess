//
//  DockerImagesView.swift
//  dsmaccess
//
//  “Images” tab of the Containers module: local inventory, download from the registry,
//  deletion with confirmation.
//

import SwiftUI
import UniformTypeIdentifiers

struct DockerImagesView: View {
    @Bindable var vm: DockerImagesViewModel
    @State private var order = [KeyPathComparator(\DockerImage.displayName)]
    @State private var selection: DockerImage.ID?
    @State private var pendingDelete: DockerImage?
    @State private var detailedImage: DockerImage?
    @State private var archiveMode: ArchiveMode?
    @State private var isImportingFromMac = false
    @State private var isPresentingPull = false
    @State private var isConfirmingPrune = false
    @AccessibilityFocusState private var focusContent: Bool

    /// `.sheet(item:)` needs something identifiable, and what the sheet shows has to travel
    /// with its presentation rather than be read from a separate state when it draws.
    private struct ArchiveMode: Identifiable {
        let kind: DockerImageArchiveSheet.Mode

        var id: String {
            switch kind {
            case .export(let image): "export-\(image.id)"
            case .importArchive: "import"
            }
        }
    }

    var body: some View {
        content
            .task {
                await load(announce: false)
                focusContent = true
            }
            .sheet(isPresented: $isPresentingPull) {
                DockerImagePullSheet(vm: vm)
            }
            .sheet(item: $detailedImage) { image in
                DockerImageDetailSheet(image: image, vm: vm)
            }
            .sheet(item: $archiveMode) { mode in
                DockerImageArchiveSheet(mode: mode.kind, vm: vm)
            }
            .fileImporter(
                isPresented: $isImportingFromMac,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await sendFromMac(url) }
                case .failure(let error):
                    VoiceOver.announce(
                        .failure(error.localizedDescription),
                        priority: .high
                    )
                }
            }
            .confirmationDialog(
                "containers.image.prune.confirm.title",
                isPresented: $isConfirmingPrune
            ) {
                Button("containers.image.prune", role: .destructive) {
                    Task { VoiceOver.announce(await vm.prune(), priority: .high) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                Text("containers.image.prune.confirm.message")
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("common.button.delete", role: .destructive) {
                    guard let image = pendingDelete else { return }
                    pendingDelete = nil
                    Task { VoiceOver.announce(await vm.delete(image), priority: .high) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                if let image = pendingDelete {
                    Text(String(
                        localized: "containers.image.delete.confirm.message",
                        defaultValue: "The image “\(image.displayName)” will be removed from the NAS. A container that still needs it will no longer find it. This cannot be undone; the image can be downloaded again."
                    ))
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.images.isEmpty {
            ModuleLoadingView("containers.image.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage = vm.errorMessage, vm.images.isEmpty {
            ModuleErrorView(message: errorMessage) {
                Task { await load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else if vm.images.isEmpty {
            EmptyModuleView(
                title: "containers.image.empty.title",
                systemImage: "cube",
                description: "containers.image.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Table(
                    vm.images.sorted(using: order),
                    selection: $selection,
                    sortOrder: $order
                ) {
                    TableColumn("common.column.name", value: \.repository)
                    TableColumn("containers.image.column.tag", value: \.sortableTag) { image in
                        Text(image.tags.isEmpty ? "—" : image.tags.joined(separator: ", "))
                    }
                    TableColumn("common.column.size", value: \.sortableSize) { image in
                        Text(image.sizeBytes?.formatted(.byteCount(style: .file)) ?? "—")
                    }
                    TableColumn("common.column.creation_date", value: \.sortableCreatedAt) { image in
                        Text(image.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    }
                    TableColumn("containers.image.column.update", value: \.sortableUpgradable) { image in
                        // The word, not just a badge: an update only signalled by an icon
                        // stays invisible to the screen reader.
                        Text(image.isUpgradable
                             ? String(localized: "containers.image.update.available")
                             : String(localized: "containers.image.update.up_to_date"))
                    }
                }
                .accessibilityLabel("containers.tab.images")
                .accessibilityFocused($focusContent)
                .contextMenu(forSelectionType: DockerImage.ID.self) { ids in
                    if let image = vm.images.first(where: { ids.contains($0.id) }) {
                        Button("containers.image.action.detail") { detailedImage = image }
                        Divider()
                        Button("common.button.delete", role: .destructive) { pendingDelete = image }
                    }
                }

                actionBar

                Text(vm.summary)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("containers.image.action.pull") {
                isPresentingPull = true
            }
            .disabled(vm.isPulling)
            .help("containers.image.action.pull.hint")

            Button("containers.image.action.detail") {
                detailedImage = selectedImage
            }
            .disabled(selectedImage == nil)
            .help("containers.image.action.detail.hint")

            Button("containers.image.action.upgrade") {
                guard let image = selectedImage else { return }
                Task { VoiceOver.announce(await vm.upgrade(image), priority: .high) }
            }
            .disabled(selectedImage?.isUpgradable != true || selectedIsBusy || vm.isPulling)
            .help("containers.image.action.upgrade.hint")

            Menu("containers.image.action.transfer") {
                Button("containers.image.import.from_nas") {
                    archiveMode = ArchiveMode(kind: .importArchive)
                }
                Button("containers.image.import.from_mac") {
                    isImportingFromMac = true
                }
                Divider()
                Button("containers.image.action.export") {
                    guard let image = selectedImage else { return }
                    archiveMode = ArchiveMode(kind: .export(image))
                }
                .disabled(selectedImage == nil)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(vm.isTransferring || vm.isPulling)
            .help("containers.image.action.transfer.hint")

            Button("containers.image.prune") {
                isConfirmingPrune = true
            }
            .disabled(vm.isPulling)
            .help("containers.image.prune.hint")

            Button("common.button.delete", role: .destructive) {
                pendingDelete = selectedImage
            }
            .disabled(selectedImage == nil || selectedIsBusy)
            .help("containers.image.action.delete.hint")

            if let progress = vm.pullDescription ?? vm.transferDescription {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var selectedImage: DockerImage? {
        vm.images.first { $0.id == selection }
    }

    private var selectedIsBusy: Bool {
        guard let selectedImage else { return false }
        return vm.busyImageIDs.contains(selectedImage.id)
    }

    private var deleteTitle: Text {
        Text(String(
            localized: "containers.image.delete.confirm.title",
            defaultValue: "Delete “\(pendingDelete?.displayName ?? "")”?"
        ))
    }

    /// Sending a file the sandbox does not otherwise reach: the panel hands over a
    /// security-scoped URL, and access has to be held for the whole upload.
    private func sendFromMac(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        VoiceOver.announce(
            String(localized: "containers.image.upload.in_progress"),
            category: .progress
        )
        VoiceOver.announce(await vm.uploadImage(at: url), priority: .high)
    }

    private func load(announce: Bool) async {
        await vm.load()
        guard announce, !Task.isCancelled else { return }
        VoiceOver.announce(vm.summary, category: vm.errorMessage == nil ? .result : .error)
    }
}

extension DockerImage {
    var sortableTag: String { tags.first ?? "" }
    var sortableSize: Int64 { sizeBytes ?? 0 }
    var sortableCreatedAt: Date { createdAt ?? .distantPast }
    /// `TableColumn` sorts on Comparable values, which Bool is not.
    var sortableUpgradable: Int { isUpgradable ? 1 : 0 }
}

/// Download form: repository and tag, then progress until the registry hands the image over.
struct DockerImagePullSheet: View {
    @Bindable var vm: DockerImagesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var repository = ""
    @State private var tag = ""
    @AccessibilityFocusState private var focusRepository: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("containers.image.pull.repository", text: $repository, prompt: Text(verbatim: "nginx"))
                        .accessibilityFocused($focusRepository)
                        .autocorrectionDisabled()
                    TextField("containers.image.pull.tag", text: $tag, prompt: Text(verbatim: "latest"))
                        .autocorrectionDisabled()
                } footer: {
                    if let registryName = vm.registryName {
                        Text(String(
                            localized: "containers.image.pull.registry_note",
                            defaultValue: "The image will be downloaded from \(registryName)."
                        ))
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("containers.image.pull.title")
            .navigationTitle("containers.image.pull.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("containers.image.action.pull") {
                        let repository = repository.trimmingCharacters(in: .whitespaces)
                        let tag = tag.trimmingCharacters(in: .whitespaces)
                        dismiss()
                        Task {
                            VoiceOver.announce(
                                await vm.pull(repository: repository, tag: tag),
                                priority: .high
                            )
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(repository.trimmingCharacters(in: .whitespaces).isEmpty || vm.isPulling)
                    .help("containers.image.action.pull.hint")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.button.cancel") { dismiss() }
                        .help("containers.image.pull.cancel.hint")
                }
            }
        }
        .frame(minWidth: 420)
        .task {
            await Task.yield()
            focusRepository = true
        }
    }
}
