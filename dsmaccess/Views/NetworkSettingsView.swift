//
//  NetworkSettingsView.swift
//  dsmaccess
//
//  Sous-module « Réseau et identité » du Panneau de configuration : affiche l'identité et la
//  configuration réseau du NAS (nom, adresse IP, passerelle, DNS…). Lecture seule pour l'instant.
//  Chaque carte est un élément VoiceOver combiné, comme StorageView.
//

import SwiftUI

struct NetworkSettingsView: View {
    @State private var vm: NetworkSettingsViewModel
    @AccessibilityFocusState private var focusTitle: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: NetworkSettingsViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Réseau et identité")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusTitle)

                content
            }
            .padding(28)
            .frame(maxWidth: 540, alignment: .leading)
        }
        .task {
            focusTitle = true
            await vm.load()
            // Tâche annulée (vue quittée avant la fin) : ne rien annoncer.
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(vm.summary).post()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.info == nil {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Chargement…").foregroundStyle(.secondary)
            }
        } else if let error = vm.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Text(error).foregroundStyle(.red)
                Button("Réessayer") {
                    Task { await vm.load(); AccessibilityNotification.Announcement(vm.summary).post() }
                }
            }
        } else if let info = vm.info {
            identitySection(info)
            networkSection(info)
        }
    }

    private func identitySection(_ info: NetworkInfo) -> some View {
        section("Identité") {
            card {
                if let name = info.serverName, !name.isEmpty {
                    row("Nom du serveur", name)
                }
                if info.enableWinDomain == true {
                    row("Domaine Windows", String(localized: "Activé"))
                }
            }
        }
    }

    private func networkSection(_ info: NetworkInfo) -> some View {
        section("Réseau") {
            card {
                if let ip = info.gatewayInfo?.ip, !ip.isEmpty {
                    row("Adresse IP", ip)
                }
                if let mask = info.gatewayInfo?.mask, !mask.isEmpty {
                    row("Masque de sous-réseau", mask)
                }
                if let gateway = info.gateway, !gateway.isEmpty {
                    row("Passerelle par défaut", gateway)
                }
                if let dns = dnsText(info) {
                    row("Serveur DNS", dns)
                }
                if let mode = dnsModeText(info) {
                    row("Configuration DNS", mode)
                }
                if let v6 = info.v6gateway, !v6.isEmpty {
                    row("Passerelle IPv6", v6)
                }
                if let iface = interfaceText(info) {
                    row("Interface", iface)
                }
            }
        }
    }

    // MARK: - Présentation

    private func dnsText(_ info: NetworkInfo) -> String? {
        let servers = [info.dnsPrimary, info.dnsSecondary]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return servers.isEmpty ? nil : servers.joined(separator: ", ")
    }

    private func dnsModeText(_ info: NetworkInfo) -> String? {
        guard let manual = info.dnsManual else { return nil }
        return manual ? String(localized: "Manuelle") : String(localized: "Automatique (DHCP)")
    }

    private func interfaceText(_ info: NetworkInfo) -> String? {
        guard let name = info.gatewayInfo?.ifname, !name.isEmpty else { return nil }
        if info.gatewayInfo?.useDhcp == true {
            return String(localized: "\(name) (DHCP)")
        }
        return name
    }

    // MARK: - Composants (mêmes cartes que StorageView)

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
