//
//  ResourceMonitorView.swift
//  dsmaccess
//
//  Section « Ressources en direct » du module Votre NAS : processeur, mémoire et réseau
//  instantanés, en cartes VoiceOver combinées (comme le module Stockage). Deux façons
//  d'actualiser : bouton manuel (réannonce le résumé) et interrupteur d'actualisation
//  automatique (mises à jour silencieuses toutes les 5 s, pensé pour le lecteur d'écran).
//

import SwiftUI

struct ResourceMonitorView: View {
    @State private var vm: SystemResourcesViewModel

    init(session: SessionStore) {
        _vm = State(initialValue: SystemResourcesViewModel(session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ressources en direct")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    Task { await vm.load(announce: true) }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .accessibilityHint("Recharge les valeurs et les annonce")
            }

            content

            Toggle("Actualisation automatique", isOn: $vm.autoRefresh)
                .accessibilityHint("Met à jour les valeurs toutes les 5 secondes")
        }
        .task { await vm.load() }
        .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.usage == nil {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Chargement…").foregroundStyle(.secondary)
            }
        } else if let error = vm.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).foregroundStyle(.red)
                Button("Réessayer") {
                    Task { await vm.load(announce: true) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                card {
                    Text("Processeur").fontWeight(.medium)
                    row("Charge", vm.cpuText)
                    if let detail = vm.cpuDetailText {
                        Text(detail).foregroundStyle(.secondary).font(.callout)
                    }
                }
                card {
                    Text("Mémoire vive").fontWeight(.medium)
                    row("Utilisation", vm.memoryText)
                    if let detail = vm.memoryDetailText {
                        Text(detail).foregroundStyle(.secondary).font(.callout)
                    }
                    if let swap = vm.swapText { row("Fichier d'échange", swap) }
                }
                card {
                    Text("Réseau").fontWeight(.medium)
                    row("Réception", vm.networkDownText)
                    row("Envoi", vm.networkUpText)
                }
            }
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
