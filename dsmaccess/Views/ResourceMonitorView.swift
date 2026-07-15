//
//  ResourceMonitorView.swift
//  dsmaccess
//
//  Mesures instantanées du processeur, de la mémoire et du réseau.
//

import SwiftUI

struct ResourceMonitorView: View {
    @State private var vm: SystemResourcesViewModel

    init(session: SessionStore) {
        _vm = State(initialValue: SystemResourcesViewModel(session: session))
    }

    var body: some View {
        Section {
            content
            Toggle("Actualisation automatique", isOn: $vm.autoRefresh)
                .accessibilityHint("Met à jour les valeurs toutes les 5 secondes")
                .help("Actualiser automatiquement les ressources toutes les cinq secondes")
        } header: {
            HStack {
                Text("Ressources en direct")
                Spacer()
                Button {
                    Task { await vm.load(announce: true) }
                } label: {
                    Label("Actualiser les ressources", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Actualiser les ressources")
            }
        }
        .task { await vm.load() }
        .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.usage == nil {
            HStack {
                ProgressView().controlSize(.small)
                Text("Chargement…").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if let error = vm.errorMessage {
            LabeledContent("Erreur", value: error)
        } else {
            LabeledContent("Charge du processeur", value: vm.cpuText)
            if let detail = vm.cpuDetailText {
                LabeledContent("Détail du processeur", value: detail)
            }
            LabeledContent("Utilisation de la mémoire", value: vm.memoryText)
            if let detail = vm.memoryDetailText {
                LabeledContent("Détail de la mémoire", value: detail)
            }
            if let swap = vm.swapText {
                LabeledContent("Fichier d’échange", value: swap)
            }
            LabeledContent("Réception réseau", value: vm.networkDownText)
            LabeledContent("Envoi réseau", value: vm.networkUpText)
        }
    }
}
