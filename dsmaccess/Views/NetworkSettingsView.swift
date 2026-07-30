//
//  NetworkSettingsView.swift
//  dsmaccess
//
//  Affiche l'identité et la configuration réseau du NAS.
//

import SwiftUI

struct NetworkSettingsView: View {
    @State private var vm: NetworkSettingsViewModel
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: NetworkSettingsViewModel(session: session))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.info == nil {
                ModuleLoadingView("network.loading")
                    .accessibilityFocused($focusContent)
            } else if let error = vm.errorMessage {
                ModuleErrorView(message: error) {
                    Task { await load() }
                }
                .accessibilityFocused($focusContent)
            } else if let info = vm.info {
                List {
                    identitySection(info)
                    networkSection(info)
                }
                .accessibilityFocused($focusContent)
            } else {
                EmptyModuleView(
                    title: "common.error.network_configuration_unavailable",
                    systemImage: "network.slash",
                    description: "network.empty.description"
                )
                .accessibilityFocused($focusContent)
            }
        }
        .navigationTitle("common.section.network_identity")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("network.refresh.button")
            }
        }
        .task { await load(restoresInitialFocus: true) }
    }

    private func identitySection(_ info: NetworkInfo) -> some View {
        Section("network.identity.section") {
            if let name = info.serverName, !name.isEmpty {
                LabeledContent("network.identity.server_name", value: name)
            }
            if info.enableWinDomain == true {
                LabeledContent("network.identity.windows_domain", value: String(localized: "common.status.enabled.masculine"))
            }
        }
    }

    private func networkSection(_ info: NetworkInfo) -> some View {
        Section("common.label.network") {
            if let ip = info.gatewayInfo?.ip, !ip.isEmpty {
                LabeledContent("network.interface.ip_address", value: ip)
            }
            if let mask = info.gatewayInfo?.mask, !mask.isEmpty {
                LabeledContent("network.interface.subnet_mask", value: mask)
            }
            if let gateway = info.gateway, !gateway.isEmpty {
                LabeledContent("network.gateway.default", value: gateway)
            }
            if let dns = dnsText(info) {
                LabeledContent("network.dns.server", value: dns)
            }
            if let mode = dnsModeText(info) {
                LabeledContent("network.dns.configuration", value: mode)
            }
            if let v6 = info.v6gateway, !v6.isEmpty {
                LabeledContent("network.gateway.ipv6", value: v6)
            }
            if let interface = interfaceText(info) {
                LabeledContent("network.interface.label", value: interface)
            }
        }
    }

    private func dnsText(_ info: NetworkInfo) -> String? {
        let servers = [info.dnsPrimary, info.dnsSecondary]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return servers.isEmpty ? nil : servers.joined(separator: ", ")
    }

    private func dnsModeText(_ info: NetworkInfo) -> String? {
        guard let manual = info.dnsManual else { return nil }
        return manual ? String(localized: "network.configuration.manual") : String(localized: "network.configuration.automatic")
    }

    private func interfaceText(_ info: NetworkInfo) -> String? {
        guard let name = info.gatewayInfo?.ifname, !name.isEmpty else { return nil }
        if info.gatewayInfo?.useDhcp == true {
            return String(localized: "network.interface.address.dhcp", defaultValue: "\(name) (DHCP)")
        }
        return name
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "network.loading"),
            category: .progress,
            priority: .low
        )
        await vm.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        }
        VoiceOver.announce(
            vm.summary,
            category: vm.errorMessage == nil ? .result : .error
        )
    }
}
