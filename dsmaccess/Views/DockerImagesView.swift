//
//  DockerImagesView.swift
//  dsmaccess
//
//  “Images” tab of the Containers module: local inventory, download from the registry,
//  deletion with confirmation.
//

import SwiftUI

struct DockerImagesView: View {
    @Bindable var vm: DockerImagesViewModel
    @State private var order = [KeyPathComparator(\DockerImage.displayName)]
    @State private var selection: DockerImage.ID?
    @State private var pendingDelete: DockerImage?
    @State private var isPresentingPull = false
    @State private var isConfirmingPrune = false
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await load(announce: false)
                focusContent = true
            }
            .sheet(isPresented: $isPresentingPull) {
                DockerImagePullSheet(vm: vm)
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

            Button("containers.image.action.upgrade") {
                guard let image = selectedImage else { return }
                Task { VoiceOver.announce(await vm.upgrade(image), priority: .high) }
            }
            .disabled(selectedImage?.isUpgradable != true || selectedIsBusy || vm.isPulling)
            .help("containers.image.action.upgrade.hint")

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

            if vm.isPulling, let pullDescription = vm.pullDescription {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(pullDescription)
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
