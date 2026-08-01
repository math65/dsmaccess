//
//  DockerNetworksView.swift
//  dsmaccess
//
//  “Networks” tab of the Containers module: name, driver, addressing and the containers
//  attached to each network, plus creating, removing and rewiring them.
//

import SwiftUI

struct DockerNetworksView: View {
    @Bindable var vm: DockerNetworksViewModel
    @State private var order = [KeyPathComparator(\DockerNetwork.name)]
    @State private var selection: DockerNetwork.ID?
    @State private var showsCreation = false
    @State private var managedNetwork: DockerNetwork?
    @State private var pendingRemoval: DockerNetwork?
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await load(announce: false)
                focusContent = true
            }
            .sheet(isPresented: $showsCreation) {
                DockerNetworkCreationSheet(vm: vm)
            }
            .sheet(item: $managedNetwork) { network in
                DockerNetworkContainersSheet(network: network, vm: vm)
            }
            .confirmationDialog(
                removalTitle,
                isPresented: Binding(
                    get: { pendingRemoval != nil },
                    set: { if !$0 { pendingRemoval = nil } }
                )
            ) {
                Button("common.button.delete", role: .destructive) {
                    guard let network = pendingRemoval else { return }
                    pendingRemoval = nil
                    Task { VoiceOver.announce(await vm.remove(network), priority: .high) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                if let network = pendingRemoval {
                    Text(removalMessage(for: network))
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.networks.isEmpty {
            ModuleLoadingView("containers.network.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage = vm.errorMessage, vm.networks.isEmpty {
            ModuleErrorView(message: errorMessage) {
                Task { await load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if vm.networks.isEmpty {
                    // Same reason as the projects tab: the action bar has to stay reachable
                    // from the empty state, since creating is what is wanted there.
                    EmptyModuleView(
                        title: "containers.network.empty.title",
                        systemImage: "network",
                        description: "containers.network.empty.description"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityFocused($focusContent)
                } else {
                Table(
                    vm.networks.sorted(using: order),
                    selection: $selection,
                    sortOrder: $order
                ) {
                    TableColumn("common.column.name", value: \.name)
                    TableColumn("containers.network.column.driver", value: \.driver)
                    TableColumn("containers.network.column.subnet", value: \.sortableSubnet) { network in
                        Text(network.subnet ?? "—")
                    }
                    TableColumn("containers.network.column.gateway", value: \.sortableGateway) { network in
                        Text(network.gateway ?? "—")
                    }
                    TableColumn("containers.network.column.ipv6", value: \.sortableIPv6) { network in
                        Text(network.enablesIPv6
                             ? String(localized: "common.status.enabled.masculine")
                             : String(localized: "common.status.disabled.masculine"))
                    }
                    TableColumn("containers.network.column.containers", value: \.containerCount) { network in
                        Text(network.containerNames.isEmpty
                             ? "—"
                             : network.containerNames.joined(separator: ", "))
                    }
                }
                .accessibilityLabel("containers.tab.networks")
                .accessibilityFocused($focusContent)
                .contextMenu(forSelectionType: DockerNetwork.ID.self) { ids in
                    if let network = vm.networks.first(where: { ids.contains($0.id) }) {
                        networkActions(network)
                    }
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
            Button("containers.network.action.create") {
                showsCreation = true
            }
            .help("containers.network.action.create.hint")

            Button("containers.network.action.containers") {
                managedNetwork = selectedNetwork
            }
            .disabled(selectedNetwork == nil || selectedIsBusy)
            .help("containers.network.action.containers.hint")

            Button("common.button.delete", role: .destructive) {
                pendingRemoval = selectedNetwork
            }
            .disabled(!canRemoveSelection)
            .help("containers.network.action.delete.hint")

            if selectedIsBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("containers.network.action.in_progress")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func networkActions(_ network: DockerNetwork) -> some View {
        Button("containers.network.action.containers") { managedNetwork = network }
        if !network.isBuiltIn {
            Divider()
            Button("common.button.delete", role: .destructive) { pendingRemoval = network }
        }
    }

    private var selectedNetwork: DockerNetwork? {
        vm.networks.first { $0.id == selection }
    }

    private var selectedIsBusy: Bool {
        guard let selectedNetwork else { return false }
        return vm.busyNetworkNames.contains(selectedNetwork.name)
    }

    /// `bridge` and `host` come from Docker itself and cannot be removed; DSM greys the action
    /// out for them and the app does the same.
    private var canRemoveSelection: Bool {
        guard let selectedNetwork, !selectedIsBusy else { return false }
        return !selectedNetwork.isBuiltIn
    }

    private var removalTitle: Text {
        Text(String(
            localized: "containers.network.remove.confirm.title",
            defaultValue: "Remove “\(pendingRemoval?.name ?? "")”?"
        ))
    }

    private func removalMessage(for network: DockerNetwork) -> String {
        guard !network.containerNames.isEmpty else {
            return String(
                localized: "containers.network.remove.confirm.message",
                defaultValue: "The network “\(network.name)” will be removed from Container Manager."
            )
        }
        // DSM's daemon refuses to remove a network that still carries containers, so saying
        // which ones is more useful than a warning that the removal may fail.
        return String(
            localized: "containers.network.remove.confirm.message_in_use",
            defaultValue: "The network “\(network.name)” still carries \(network.containerNames.joined(separator: ", ")). Docker refuses to remove a network in use: disconnect them first."
        )
    }

    private func load(announce: Bool) async {
        await vm.load()
        guard announce, !Task.isCancelled else { return }
        VoiceOver.announce(vm.summary, category: vm.errorMessage == nil ? .result : .error)
    }
}

extension DockerNetwork {
    var sortableSubnet: String { subnet ?? "" }
    var sortableGateway: String { gateway ?? "" }
    /// `TableColumn` sorts on Comparable values, which Bool is not.
    var sortableIPv6: Int { enablesIPv6 ? 1 : 0 }
}
