//
//  DockerRegistriesView.swift
//  dsmaccess
//
//  “Registries” tab of the Containers module: the repositories images are downloaded from,
//  which one is active, and searching that one for an image to pull.
//

import SwiftUI

struct DockerRegistriesView: View {
    @Bindable var vm: DockerRegistriesViewModel
    /// Downloading belongs to the Images tab, which owns the pull and its progress; the search
    /// sheet hands it a repository and a tag rather than running a second download of its own.
    let images: DockerImagesViewModel

    @State private var order = [KeyPathComparator(\RegistryRow.name)]
    @State private var selection: RegistryRow.ID?
    @State private var form: FormMode?
    @State private var showsSearch = false
    @State private var pendingDeletion: DockerRegistry?
    @AccessibilityFocusState private var focusContent: Bool

    /// One row of the table. The active registry is a property of the list rather than of a
    /// registry, and the column has to be sortable like the others.
    private struct RegistryRow: Identifiable {
        let registry: DockerRegistry
        let isActive: Bool

        var id: String { registry.id }
        var name: String { registry.name }
        var url: String { registry.url }
        var sortableActive: Int { isActive ? 1 : 0 }

        var activeLabel: String {
            isActive
                ? String(localized: "containers.registry.status.active")
                : String(localized: "containers.registry.status.inactive")
        }

        var accountLabel: String {
            registry.username.isEmpty
                ? String(localized: "containers.registry.account.none")
                : registry.username
        }
    }

    private enum FormMode: Identifiable {
        case create
        case edit(DockerRegistry)

        var id: String {
            switch self {
            case .create: "create"
            case .edit(let registry): "edit-\(registry.name)"
            }
        }
    }

    var body: some View {
        content
            .task {
                await load(announce: false)
                focusContent = true
            }
            .sheet(item: $form) { mode in
                switch mode {
                case .create:
                    DockerRegistryEditSheet(vm: vm, registry: nil)
                case .edit(let registry):
                    DockerRegistryEditSheet(vm: vm, registry: registry)
                }
            }
            .sheet(isPresented: $showsSearch) {
                DockerImageSearchSheet(vm: vm, images: images)
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                )
            ) {
                Button("common.button.delete", role: .destructive) {
                    guard let registry = pendingDeletion else { return }
                    pendingDeletion = nil
                    Task { OperationFailures.shared.present(await vm.delete(registry), from: .containers) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                if let registry = pendingDeletion {
                    Text(deletionMessage(for: registry))
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.registries.isEmpty {
            ModuleLoadingView("containers.registry.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage = vm.errorMessage, vm.registries.isEmpty {
            ModuleErrorView(message: errorMessage) {
                Task { await load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Table(rows.sorted(using: order), selection: $selection, sortOrder: $order) {
                    TableColumn("containers.registry.column.repository", value: \.name)
                    TableColumn("containers.registry.column.url", value: \.url)
                    TableColumn("containers.registry.column.active", value: \.sortableActive) { row in
                        // Never the colour alone: the word is what carries the state.
                        Text(row.activeLabel)
                            .foregroundStyle(row.isActive ? AnyShapeStyle(.readableGreen) : AnyShapeStyle(.readableSecondary))
                    }
                    TableColumn("containers.registry.column.account", value: \.accountLabel)
                }
                .accessibilityLabel("containers.tab.registries")
                .accessibilityFocused($focusContent)
                .contextMenu(forSelectionType: RegistryRow.ID.self) { ids in
                    if let row = rows.first(where: { ids.contains($0.id) }) {
                        registryActions(row)
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
            Button("containers.registry.action.search") { showsSearch = true }
                .help("containers.registry.action.search.hint")

            Button("containers.registry.action.add") { form = .create }
                .help("containers.registry.action.add.hint")

            Button("common.button.edit") {
                guard let registry = selectedRegistry else { return }
                form = .edit(registry)
            }
            .disabled(selectedRegistry == nil || selectedIsBusy)
            .help("containers.registry.action.edit.hint")

            Button("containers.registry.action.use") {
                guard let registry = selectedRegistry else { return }
                Task { OperationFailures.shared.present(await vm.use(registry), from: .containers) }
            }
            .disabled(!canUseSelection)
            .help("containers.registry.action.use.hint")

            Button("common.button.delete", role: .destructive) {
                pendingDeletion = selectedRegistry
            }
            .disabled(!canDeleteSelection)
            .help("containers.registry.action.delete.hint")

            if selectedIsBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("containers.registry.action.in_progress")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func registryActions(_ row: RegistryRow) -> some View {
        Button("common.button.edit") { form = .edit(row.registry) }
        if !row.isActive {
            Button("containers.registry.action.use") {
                Task { OperationFailures.shared.present(await vm.use(row.registry), from: .containers) }
            }
        }
        if !row.registry.isDefaultRegistry {
            Divider()
            Button("common.button.delete", role: .destructive) { pendingDeletion = row.registry }
        }
    }

    private var rows: [RegistryRow] {
        vm.registries.map {
            RegistryRow(registry: $0, isActive: $0.name == vm.activeRegistryName)
        }
    }

    private var selectedRegistry: DockerRegistry? {
        vm.registries.first { $0.id == selection }
    }

    private var selectedIsBusy: Bool {
        guard let selectedRegistry else { return false }
        return vm.busyRegistryNames.contains(selectedRegistry.name)
    }

    /// Docker Hub is the registry DSM ships with and refuses to remove, and it identifies it by
    /// name rather than by the `syno` flag.
    private var canDeleteSelection: Bool {
        guard let selectedRegistry, !selectedIsBusy else { return false }
        return !selectedRegistry.isDefaultRegistry
    }

    private var canUseSelection: Bool {
        guard let selectedRegistry, !selectedIsBusy else { return false }
        return selectedRegistry.name != vm.activeRegistryName
    }

    private var deletionTitle: Text {
        Text(String(
            localized: "containers.registry.delete.confirm.title",
            defaultValue: "Remove “\(pendingDeletion?.name ?? "")”?"
        ))
    }

    private func deletionMessage(for registry: DockerRegistry) -> String {
        guard registry.name == vm.activeRegistryName else {
            return String(
                localized: "containers.registry.delete.confirm.message",
                defaultValue: "The registry “\(registry.name)” will be removed from the list. The images already downloaded from it are kept."
            )
        }
        return String(
            localized: "containers.registry.delete.confirm.message_active",
            defaultValue: "“\(registry.name)” is the registry images are currently downloaded from. Removing it leaves no active registry until you choose another one."
        )
    }

    private func load(announce: Bool) async {
        await vm.load()
        guard announce, !Task.isCancelled else { return }
        VoiceOver.announce(vm.summary, category: vm.errorMessage == nil ? .result : .error)
    }
}
