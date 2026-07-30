//
//  ResourceMonitorView.swift
//  dsmaccess
//
//  Resource monitor: instantaneous measurements of the processor, memory, network, disks and
//  volumes. Grouped by topic rather than in one long flat list, so that the headings serve as
//  jump points for the screen reader.
//

import SwiftUI

struct ResourceMonitorView: View {
    /// DSM's tabs, in the same order. Each one loads and refreshes its own measurements:
    /// switching to "Tasks" must not keep polling the resources.
    private enum Pane: String, CaseIterable, Identifiable {
        case performance
        case tasks
        case connections
        case openedFiles
        case history
        case alarm

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .performance: "monitor.tab.performance"
            case .tasks: "monitor.tab.tasks"
            case .connections: "monitor.tab.connections"
            case .openedFiles: "common.label.open_files"
            case .history: "monitor.tab.history"
            case .alarm: "monitor.tab.alarm"
            }
        }
    }

    @State private var pane = Pane.performance
    @State private var vm: SystemResourcesViewModel
    @State private var tasks: TaskManagerViewModel
    @State private var connections: ConnectionsViewModel
    @State private var openedFiles: OpenedFilesViewModel
    @State private var history: ResourceMonitorHistoryViewModel
    @State private var alarm: PerformanceAlarmViewModel
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: SystemResourcesViewModel(session: session))
        _tasks = State(initialValue: TaskManagerViewModel(session: session))
        _connections = State(initialValue: ConnectionsViewModel(session: session))
        _openedFiles = State(initialValue: OpenedFilesViewModel(session: session))
        _history = State(initialValue: ResourceMonitorHistoryViewModel(session: session))
        _alarm = State(initialValue: PerformanceAlarmViewModel(session: session))
    }

    var body: some View {
        // A TabView and not a segmented picker: the latter announces itself as radio buttons,
        // whereas tabs present themselves as tabs and are navigated as such.
        // Wrapped in a VStack so the tabs stay inside the content: placed at the root of the
        // pane, macOS lifts them into the toolbar, where they take the place of the module
        // title.
        VStack(spacing: 0) {
            TabView(selection: $pane) {
                performance
                    .tabItem { Text("monitor.tab.performance") }
                    .tag(Pane.performance)
                TaskManagerView(vm: tasks)
                    .tabItem { Text("monitor.tab.tasks") }
                    .tag(Pane.tasks)
                ConnectionsView(vm: connections)
                    .tabItem { Text("monitor.tab.connections") }
                    .tag(Pane.connections)
                OpenedFilesView(vm: openedFiles)
                    .tabItem { Text("common.label.open_files") }
                    .tag(Pane.openedFiles)
                ResourceMonitorHistoryView(vm: history)
                    .tabItem { Text("monitor.tab.history") }
                    .tag(Pane.history)
                PerformanceAlarmView(vm: alarm)
                    .tabItem { Text("monitor.tab.alarm") }
                    .tag(Pane.alarm)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        switch pane {
                        case .performance: await vm.load(announce: true)
                        case .tasks: await tasks.load(announce: true)
                        case .connections: await connections.load(announce: true)
                        case .openedFiles: await openedFiles.load(announce: true)
                        case .history: await history.load(announce: true)
                        case .alarm: await alarm.load(announce: true)
                        }
                    }
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("monitor.refresh.hint")
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
            ModuleLoadingView("monitor.loading")
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

                Section("common.metric.processor") {
                    LabeledContent("monitor.load.label", value: vm.cpuText)
                    if let detail = vm.cpuDetailText {
                        LabeledContent("monitor.column.detail", value: detail)
                    }
                    if let load = vm.loadAverageText {
                        LabeledContent("monitor.load_average.label", value: load)
                    }
                }

                Section("common.metric.memory") {
                    LabeledContent("common.column.usage", value: vm.memoryText)
                    if let detail = vm.memoryDetailText {
                        LabeledContent("monitor.column.detail", value: detail)
                    }
                    if let swap = vm.swapText {
                        LabeledContent("monitor.memory.swap", value: swap)
                    }
                }

                Section("common.label.network") {
                    LabeledContent("monitor.network.received", value: vm.networkDownText)
                    LabeledContent("common.status.sending", value: vm.networkUpText)
                }

                if !vm.disks.isEmpty {
                    Section("common.label.disks") {
                        ForEach(vm.disks) { disk in
                            LabeledContent(disk.name, value: vm.activityText(for: disk))
                                .accessibilityLabel(Text(String(localized: "monitor.disk.name", defaultValue: "Disk \(disk.name)")))
                        }
                        if vm.disks.count > 1, let total = vm.diskTotal {
                            LabeledContent("monitor.disk.all", value: vm.activityText(for: total))
                        }
                    }
                }

                if !vm.volumes.isEmpty {
                    Section("monitor.tab.volumes") {
                        ForEach(vm.volumes) { volume in
                            LabeledContent(volume.name, value: vm.activityText(for: volume))
                                .accessibilityLabel(Text(String(localized: "monitor.volume.name", defaultValue: "Volume \(volume.name)")))
                        }
                    }
                }

                Section {
                    Toggle("common.label.automatic_refresh", isOn: $vm.autoRefresh)
                        .accessibilityHint("common.label.automatic_refresh.hint")
                        .help("monitor.auto_refresh.hint")
                }
            }
            .formStyle(.grouped)
            .labeledContentStyle(.readable)
            .accessibilityFocused($focusContent)
        }
    }
}
