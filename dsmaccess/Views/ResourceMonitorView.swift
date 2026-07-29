//
//  ResourceMonitorView.swift
//  dsmaccess
//
//  Moniteur de ressources : mesures instantanées du processeur, de la mémoire, du réseau,
//  des disques et des volumes. Regroupées par thème plutôt qu'en une longue liste plate,
//  pour que les en-têtes servent de points de saut au lecteur d'écran.
//

import SwiftUI

struct ResourceMonitorView: View {
    @State private var vm: SystemResourcesViewModel
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: SystemResourcesViewModel(session: session))
    }

    var body: some View {
        content
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await vm.load(announce: true) }
                    } label: {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                    .help("Actualiser les ressources")
                }
            }
            .task {
                await vm.load()
                focusContent = true
            }
            .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.usage == nil {
            ModuleLoadingView("Chargement des ressources…")
        } else if let error = vm.errorMessage, vm.usage == nil {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
        } else {
            Form {
                if let error = vm.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.readableRed)
                    }
                }

                Section("Processeur") {
                    LabeledContent("Charge", value: vm.cpuText)
                    if let detail = vm.cpuDetailText {
                        LabeledContent("Détail", value: detail)
                    }
                    if let load = vm.loadAverageText {
                        LabeledContent("Charge moyenne", value: load)
                    }
                }

                Section("Mémoire") {
                    LabeledContent("Utilisation", value: vm.memoryText)
                    if let detail = vm.memoryDetailText {
                        LabeledContent("Détail", value: detail)
                    }
                    if let swap = vm.swapText {
                        LabeledContent("Fichier d’échange", value: swap)
                    }
                }

                Section("Réseau") {
                    LabeledContent("Réception", value: vm.networkDownText)
                    LabeledContent("Envoi", value: vm.networkUpText)
                }

                if !vm.disks.isEmpty {
                    Section("Disques") {
                        ForEach(vm.disks) { disk in
                            LabeledContent(disk.name, value: vm.activityText(for: disk))
                                .accessibilityLabel(Text("Disque \(disk.name)"))
                        }
                        if vm.disks.count > 1, let total = vm.diskTotal {
                            LabeledContent("Tous les disques", value: vm.activityText(for: total))
                        }
                    }
                }

                if !vm.volumes.isEmpty {
                    Section("Volumes") {
                        ForEach(vm.volumes) { volume in
                            LabeledContent(volume.name, value: vm.activityText(for: volume))
                                .accessibilityLabel(Text("Volume \(volume.name)"))
                        }
                    }
                }

                Section {
                    Toggle("Actualisation automatique", isOn: $vm.autoRefresh)
                        .accessibilityHint("Met à jour les valeurs toutes les 5 secondes")
                        .help("Actualiser automatiquement les ressources toutes les cinq secondes")
                }
            }
            .formStyle(.grouped)
            .labeledContentStyle(.readable)
            .accessibilityFocused($focusContent)
        }
    }
}
