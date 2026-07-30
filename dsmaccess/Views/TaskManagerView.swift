//
//  TaskManagerView.swift
//  dsmaccess
//
//  "Tasks" tab of the resource monitor: the services as DSM groups them, then the most
//  active processes.
//
//  Tables rather than aligned rows: `Table` builds on NSTableView, so the headers sort with
//  a click like everywhere else on the Mac, and every value stays in its column. The two
//  tables are separated by a VSplitView: each has its own scrolling area, with a movable
//  divider, rather than two stacked lists where you no longer know which one is scrolling.
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
                // Three measurements the NAS returns that no column used to show. They are the
                // ones that answer "what is actually working?" when the Processor column shows
                // 0.0%: a service can write a lot without computing.
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

            // The scale is stated here and not on every row: the NAS returns a load summed
            // over the cores, which a single process can therefore push beyond 100%.
            // Observed on the DS920+: 251% for Plex Media Server, that is two and a half cores.
            // A separate sentence from the one above, which carries interpolations: a literal
            // percent sign in a format key must be escaped, and forgetting it only shows up in
            // English, where the string then comes out in French.
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
