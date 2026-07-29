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
    /// Les onglets de DSM, dans le même ordre. Chacun charge et actualise ses propres
    /// mesures : passer à « Tâches » ne doit pas continuer d'interroger les ressources.
    private enum Pane: String, CaseIterable, Identifiable {
        case performance
        case tasks

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .performance: "Performances"
            case .tasks: "Tâches"
            }
        }
    }

    @State private var pane = Pane.performance
    @State private var vm: SystemResourcesViewModel
    @State private var tasks: TaskManagerViewModel
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: SystemResourcesViewModel(session: session))
        _tasks = State(initialValue: TaskManagerViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Affichage", selection: $pane) {
                ForEach(Pane.allCases) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Affichage du moniteur")
            .padding(.horizontal, 12)
            .padding(.top, 8)

            switch pane {
            case .performance: performance
            case .tasks: TaskManagerView(vm: tasks)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        switch pane {
                        case .performance: await vm.load(announce: true)
                        case .tasks: await tasks.load(announce: true)
                        }
                    }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser les mesures affichées")
            }
        }
    }

    private var performance: some View {
        content
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
