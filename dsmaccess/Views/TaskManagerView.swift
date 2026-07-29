//
//  TaskManagerView.swift
//  dsmaccess
//
//  Onglet « Tâches » du moniteur de ressources : les services tels que DSM les regroupe,
//  puis les processus les plus actifs.
//
//  En tableaux et non en lignes alignées : `Table` s'appuie sur NSTableView, donc les
//  en-têtes trient d'un clic comme partout ailleurs sur le Mac, et chaque valeur reste
//  dans sa colonne. Les deux tableaux sont séparés par un VSplitView : chacun a sa propre
//  zone de défilement, avec un séparateur déplaçable, plutôt que deux listes empilées où
//  l'on ne sait plus laquelle défile.
//

import SwiftUI

struct TaskManagerView: View {
    @Bindable var vm: TaskManagerViewModel
    @State private var groupOrder = [KeyPathComparator(\ProcessGroup.sortableMemory, order: .reverse)]
    @State private var processOrder = [KeyPathComparator(\SystemProcess.sortableCPU, order: .reverse)]
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
            VStack(alignment: .leading, spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.readableRed)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                VSplitView {
                    servicesTable
                    processesTable
                }

                Toggle("Actualisation automatique", isOn: $vm.autoRefresh)
                    .accessibilityHint("Met à jour les valeurs toutes les 5 secondes")
                    .help("Actualiser automatiquement les tâches toutes les cinq secondes")
                    .padding(12)
            }
        }
    }

    private var servicesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Services")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityFocused($focusContent)

            Table(vm.groups.sorted(using: groupOrder), sortOrder: $groupOrder) {
                TableColumn("Service", value: \.displayName) { group in
                    Text(group.displayName)
                }
                TableColumn("Processeur", value: \.sortableCPU) { group in
                    Text(vm.cpuText(for: group))
                }
                TableColumn("Mémoire", value: \.sortableMemory) { group in
                    Text(vm.memoryText(for: group))
                }
                TableColumn("Processus", value: \.processCount) { group in
                    Text(group.processCount, format: .number)
                }
            }
        }
        .frame(minHeight: 160)
    }

    private var processesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Processus les plus actifs")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Table(vm.processes.sorted(using: processOrder), sortOrder: $processOrder) {
                TableColumn("Processus", value: \.name) { process in
                    Text(process.name)
                }
                TableColumn("Processeur", value: \.sortableCPU) { process in
                    Text(vm.cpuText(for: process))
                }
                TableColumn("Mémoire", value: \.sortableMemory) { process in
                    Text(vm.memoryText(for: process))
                }
            }

            Text("Les \(TaskManagerViewModel.visibleProcessCount) processus consommant le plus de processeur, sur \(vm.totalProcessCount) en cours.")
                .font(.callout)
                .foregroundStyle(.readableSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(minHeight: 160)
    }
}
