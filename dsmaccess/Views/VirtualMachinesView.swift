//
//  VirtualMachinesView.swift
//  dsmaccess
//
//  Inventaire et commandes d’alimentation de Virtual Machine Manager.
//

import SwiftUI

struct VirtualMachinesView: View {
    @State private var viewModel: VirtualMachinesViewModel
    @State private var selection: String?
    @State private var searchText = ""
    @State private var autoRefresh = true
    @State private var showInspector = false
    @State private var pendingPowerOff: VirtualMachine?
    @AccessibilityFocusState private var contentFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: VirtualMachinesViewModel(session: session))
    }

    var body: some View {
        content
            .searchable(text: $searchText, prompt: "vm.search.label")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .task(id: autoRefresh) { await refreshPeriodically() }
            .inspector(isPresented: $showInspector) { inspector }
            .confirmationDialog(
                "vm.force_off.confirm.title",
                isPresented: Binding(
                    get: { pendingPowerOff != nil },
                    set: { if !$0 { pendingPowerOff = nil } }
                ),
                presenting: pendingPowerOff
            ) { machine in
                Button(String(localized: "vm.force_off.named.label", defaultValue: "Force \(machine.name) to power off"), role: .destructive) {
                    Task { await perform(.powerOff, on: machine) }
                }
                .help(String(localized: "vm.force_off.named.label", defaultValue: "Force \(machine.name) to power off"))
                Button("common.button.cancel", role: .cancel) { }
                    .help("vm.force_off.cancel.button")
            } message: { machine in
                Text(String(localized: "vm.force_off.confirm.description", defaultValue: "“\(machine.name)” will be powered off without allowing its operating system to shut down gracefully. Data may be lost."))
            }
            .onChange(of: viewModel.machines) {
                guard let selection else { return }
                if !viewModel.machines.contains(where: { $0.id == selection }) {
                    self.selection = nil
                    showInspector = false
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.machines.isEmpty {
            ModuleLoadingView("vm.loading.label")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredMachines.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "vm.list.empty.title" : "common.empty.results",
                systemImage: "desktopcomputer",
                description: searchText.isEmpty
                    ? "vm.list.empty.description"
                    : "common.empty.results.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            List(filteredMachines, selection: $selection) { machine in
                machineRow(machine)
                    .tag(machine.id)
                    .contextMenu { machineActions(machine) }
            }
            .accessibilityLabel("common.module.virtual_machines")
            .accessibilityFocused($contentFocused)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                guard let selectedMachine else { return }
                Task { await perform(.powerOn, on: selectedMachine) }
            } label: {
                Label("common.button.start", systemImage: "play")
            }
            .disabled(selectedMachine?.canStart != true || selectedIsBusy)
            .help("vm.start.button")
        }

        ToolbarItem {
            Button {
                guard let selectedMachine else { return }
                Task { await perform(.shutdown, on: selectedMachine) }
            } label: {
                Label("vm.shutdown.button", systemImage: "stop")
            }
            .disabled(selectedMachine?.canStop != true || selectedIsBusy)
            .help("vm.shutdown.hint")
        }

        ToolbarItem {
            Menu {
                Button("vm.force_off.button", role: .destructive) {
                    pendingPowerOff = selectedMachine
                }
                .disabled(selectedMachine?.canStop != true || selectedIsBusy)
                .help("vm.force_off.hint")
                Toggle("common.label.automatic_refresh", isOn: $autoRefresh)
                    .help("vm.toolbar.auto_refresh.label")
            } label: {
                Label("vm.column.actions", systemImage: "ellipsis.circle")
            }
            .help("vm.row.more_actions.label")
        }

        ToolbarItem {
            Button {
                showInspector.toggle()
            } label: {
                Label("common.label.information", systemImage: "info.circle")
            }
            .disabled(selectedMachine == nil)
            .help(showInspector ? "vm.detail.hide.button" : "vm.detail.show.button")
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("common.button.refresh", systemImage: "arrow.clockwise")
            }
            .help("vm.toolbar.refresh.label")
        }
    }

    private func machineRow(_ machine: VirtualMachine) -> some View {
        HStack(spacing: 12) {
            Image(systemName: machine.isRunning ? "desktopcomputer.and.macbook" : "desktopcomputer")
                .foregroundStyle(machine.isRunning ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(machine.name).fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(statusText(machine.status))
                    if machine.vCPUCount > 0 { Text(String(localized: "vm.detail.vcpu_count", defaultValue: "\(machine.vCPUCount) virtual processors")) }
                    if let memory = memoryText(machine) { Text(memory) }
                }
                .font(.caption)
                .foregroundStyle(.readableSecondary)
            }
            Spacer()
            if machine.isTransitioning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "common.status.operation_in_progress", defaultValue: "Operation in progress for \(machine.name)"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(machineAccessibilityLabel(machine))
        .accessibilityActions {
            if machine.canStart {
                Button("common.button.start") { Task { await perform(.powerOn, on: machine) } }
                    .help("vm.start.hint")
            }
            if machine.canStop {
                Button("vm.shutdown.button") { Task { await perform(.shutdown, on: machine) } }
                    .help("vm.shutdown.row.hint")
                Button("vm.force_off.button", role: .destructive) {
                    pendingPowerOff = machine
                }
                .help("vm.force_off.row.hint")
            }
            Button("common.button.get_info") {
                selection = machine.id
                showInspector = true
            }
            .help("vm.detail.show.hint")
        }
    }

    @ViewBuilder
    private func machineActions(_ machine: VirtualMachine) -> some View {
        if machine.canStart {
            Button("common.button.start") { Task { await perform(.powerOn, on: machine) } }
                .help("vm.start.hint")
        }
        if machine.canStop {
            Button("vm.shutdown.button") { Task { await perform(.shutdown, on: machine) } }
                .help("vm.shutdown.row.hint")
            Divider()
            Button("vm.force_off.button", role: .destructive) { pendingPowerOff = machine }
                .help("vm.force_off.row.hint")
        }
        Divider()
        Button("common.button.get_info") {
            selection = machine.id
            showInspector = true
        }
        .help("vm.detail.show.hint")
    }

    @ViewBuilder
    private var inspector: some View {
        if let machine = selectedMachine {
            Form {
                Section("vm.column.machine") {
                    LabeledContent("common.column.name", value: machine.name)
                    LabeledContent("common.column.state", value: statusText(machine.status))
                    if let description = machine.description, !description.isEmpty {
                        LabeledContent("vm.detail.description.label", value: description)
                    }
                    LabeledContent("vm.detail.autostart.label", value: machine.autoRun ? String(localized: "common.answer.yes") : String(localized: "common.answer.no"))
                }
                Section("common.label.resources") {
                    LabeledContent("vm.detail.vcpu.label", value: machine.vCPUCount.formatted())
                    if let memory = memoryText(machine) { LabeledContent("common.metric.memory", value: memory) }
                    if let storageName = machine.storageName { LabeledContent("common.module.storage", value: storageName) }
                    LabeledContent("common.label.disks", value: machine.virtualDisks.count.formatted())
                    LabeledContent("vm.detail.network_interfaces.title", value: machine.networkInterfaces.count.formatted())
                }
                if !machine.virtualDisks.isEmpty {
                    Section("vm.detail.virtual_disks.title") {
                        ForEach(Array(machine.virtualDisks.enumerated()), id: \.offset) { index, disk in
                            LabeledContent(
                                disk.name ?? String(localized: "vm.detail.disk.label", defaultValue: "Disk \(index + 1)"),
                                value: disk.size?.formatted(.byteCount(style: .file)) ?? String(localized: "vm.detail.size_unknown")
                            )
                        }
                    }
                }
                if !machine.networkInterfaces.isEmpty {
                    Section("common.label.network") {
                        ForEach(Array(machine.networkInterfaces.enumerated()), id: \.offset) { index, interface in
                            LabeledContent(
                                interface.networkName ?? String(localized: "vm.detail.network_interface.label", defaultValue: "Interface \(index + 1)"),
                                value: interface.macAddress ?? String(localized: "vm.detail.address_unknown")
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            .accessibilityLabel(String(localized: "common.title.information_for", defaultValue: "Information for \(machine.name)"))
        } else {
            EmptyModuleView(
                title: "common.empty.selection",
                systemImage: "desktopcomputer",
                description: "vm.detail.empty.description"
            )
        }
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.summary)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.readableSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    private var filteredMachines: [VirtualMachine] {
        guard !searchText.isEmpty else { return viewModel.machines }
        return viewModel.machines.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.status.localizedStandardContains(searchText)
                || ($0.description?.localizedStandardContains(searchText) == true)
                || ($0.storageName?.localizedStandardContains(searchText) == true)
        }
    }

    private var selectedMachine: VirtualMachine? {
        viewModel.machines.first { $0.id == selection }
    }

    private var selectedIsBusy: Bool {
        guard let selection else { return false }
        return viewModel.busyIDs.contains(selection)
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "vm.loading.label"),
            category: .progress,
            priority: .low
        )
        await viewModel.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { contentFocused = true }
        }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .result : .error
        )
    }

    private func refreshPeriodically() async {
        guard autoRefresh else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, autoRefresh else { return }
            await viewModel.load(silently: true)
        }
    }

    private func perform(_ action: VirtualMachinePowerAction, on machine: VirtualMachine) async {
        VoiceOver.announce(await viewModel.perform(action, on: machine), priority: .high)
    }

    private func memoryText(_ machine: VirtualMachine) -> String? {
        guard let memoryMiB = machine.memoryMiB else { return nil }
        return (memoryMiB * 1_048_576).formatted(.byteCount(style: .memory))
    }

    private func machineAccessibilityLabel(_ machine: VirtualMachine) -> String {
        var parts = [machine.name, statusText(machine.status)]
        if machine.vCPUCount > 0 { parts.append(String(localized: "vm.detail.vcpu_count", defaultValue: "\(machine.vCPUCount) virtual processors")) }
        if let memory = memoryText(machine) { parts.append(memory) }
        return parts.formatted(.list(type: .and))
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "running": String(localized: "common.status.running")
        case "shutdown": String(localized: "vm.status.stopped")
        case "booting": String(localized: "vm.status.starting")
        case "shutting_down": String(localized: "common.status.stopping")
        case "inaccessible": String(localized: "common.status.unreachable")
        case "moving": String(localized: "common.operation.moving")
        case "stor_migrating": String(localized: "vm.status.migrating_storage")
        case "creating": String(localized: "common.label.creation")
        case "importing": String(localized: "vm.status.importing")
        case "preparing": String(localized: "vm.status.preparing")
        case "ha_standby": String(localized: "vm.status.ha_failover")
        case "crashed": String(localized: "vm.status.crashed")
        default: String(localized: "common.status.unknown")
        }
    }
}
