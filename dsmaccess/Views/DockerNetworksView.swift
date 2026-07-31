//
//  DockerNetworksView.swift
//  dsmaccess
//
//  “Networks” tab of the Containers module, read-only: name, driver, addressing and the
//  containers attached to each network.
//

import SwiftUI

struct DockerNetworksView: View {
    @Bindable var vm: DockerNetworksViewModel
    @State private var order = [KeyPathComparator(\DockerNetwork.name)]
    @State private var selection: DockerNetwork.ID?
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await load(announce: false)
                focusContent = true
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
        } else if vm.networks.isEmpty {
            EmptyModuleView(
                title: "containers.network.empty.title",
                systemImage: "network",
                description: "containers.network.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
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
                .accessibilityFocused($focusContent)

                Text(vm.summary)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
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
