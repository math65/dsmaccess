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
            ModuleLoadingView("tasks.loading")
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

                Toggle("common.label.automatic_refresh", isOn: $vm.autoRefresh)
                    .accessibilityHint("common.label.automatic_refresh.hint")
                    .help("tasks.auto_refresh.hint")
                    .padding(12)
            }
        }
    }

    private var servicesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tasks.services.tab")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityFocused($focusContent)

            Table(vm.groups.sorted(using: groupOrder), sortOrder: $groupOrder) {
                TableColumn("common.column.service", value: \.displayName) { group in
                    Text(group.displayName)
                }
                TableColumn("common.metric.processor", value: \.sortableCPU) { group in
                    Text(vm.cpuText(for: group))
                }
                TableColumn("common.metric.memory", value: \.sortableMemory) { group in
                    Text(vm.memoryText(for: group))
                }
                TableColumn("tasks.processes.tab", value: \.processCount) { group in
                    Text(group.processCount, format: .number)
                }
                // Trois mesures que le NAS renvoie et qu'aucune colonne ne montrait. Ce sont
                // elles qui répondent à « qu'est-ce qui travaille ? » quand la colonne
                // Processeur affiche 0,0 % : un service peut écrire beaucoup sans calculer.
                TableColumn("tasks.column.cpu_time", value: \.sortableCPUTime) { group in
                    Text(vm.cpuTimeText(for: group))
                }
                TableColumn("common.metric.read", value: \.sortableReadRate) { group in
                    Text(vm.readRateText(for: group))
                }
                TableColumn("common.metric.write", value: \.sortableWriteRate) { group in
                    Text(vm.writeRateText(for: group))
                }
            }
        }
        .frame(minHeight: 160)
    }

    private var processesTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tasks.processes.section.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Table(vm.processes.sorted(using: processOrder), sortOrder: $processOrder) {
                TableColumn("tasks.processes.tab", value: \.name) { process in
                    Text(process.name)
                }
                TableColumn("common.metric.processor", value: \.sortableCPU) { process in
                    Text(vm.cpuText(for: process))
                }
                TableColumn("common.metric.memory", value: \.sortableMemory) { process in
                    Text(vm.memoryText(for: process))
                }
            }

            // L'échelle est dite ici et non sur chaque ligne : le NAS renvoie une charge
            // cumulée sur les cœurs, qu'un seul processus peut donc porter au-delà de 100 %.
            // Relevé sur le DS920+ : 251 % pour Plex Media Server, soit deux cœurs et demi.
            // Phrase distincte de celle du dessus, qui porte des interpolations : un signe
            // pourcent littéral dans une clé de format doit être échappé, et l'oubli ne se
            // voit qu'en anglais, où la chaîne ressort alors en français.
            Text(String(localized: "tasks.processes.section.description", defaultValue: "The \(TaskManagerViewModel.visibleProcessCount) processes using the most processor time, out of \(vm.totalProcessCount) running."))
                .font(.callout)
                .foregroundStyle(.readableSecondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            Text("tasks.processes.cpu_over_100.footer")
                .font(.callout)
                .foregroundStyle(.readableSecondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .frame(minHeight: 160)
    }
}
