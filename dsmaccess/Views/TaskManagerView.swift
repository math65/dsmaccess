//
//  TaskManagerView.swift
//  dsmaccess
//
//  Onglet « Tâches » du moniteur de ressources : les services tels que DSM les regroupe,
//  puis les processus les plus actifs.
//

import SwiftUI

struct TaskManagerView: View {
    @Bindable var vm: TaskManagerViewModel
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await vm.load()
                focusContent = true
            }
            .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.groups.isEmpty && vm.processes.isEmpty {
            ModuleLoadingView("Chargement des tâches…")
        } else if let error = vm.errorMessage, vm.groups.isEmpty, vm.processes.isEmpty {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
        } else {
            Form {
                if let error = vm.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.readableRed)
                    }
                }

                Section {
                    ForEach(vm.groups) { group in
                        LabeledContent(group.displayName, value: vm.activityText(for: group))
                    }
                } header: {
                    Text("Services")
                } footer: {
                    Text("Processeur, mémoire et nombre de processus, par service. Un tiret signale une mesure que le NAS ne fournit pas.")
                }

                Section {
                    ForEach(vm.processes) { process in
                        LabeledContent(process.name, value: vm.activityText(for: process))
                    }
                } header: {
                    Text("Processus les plus actifs")
                } footer: {
                    Text("Les \(TaskManagerViewModel.visibleProcessCount) processus consommant le plus de processeur, sur \(vm.totalProcessCount) en cours.")
                }

                Section {
                    Toggle("Actualisation automatique", isOn: $vm.autoRefresh)
                        .accessibilityHint("Met à jour les valeurs toutes les 5 secondes")
                        .help("Actualiser automatiquement les tâches toutes les cinq secondes")
                }
            }
            .formStyle(.grouped)
            .labeledContentStyle(.readable)
            .accessibilityFocused($focusContent)
        }
    }
}
