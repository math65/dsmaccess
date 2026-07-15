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
            .searchable(text: $searchText, prompt: "Rechercher une machine virtuelle")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .task(id: autoRefresh) { await refreshPeriodically() }
            .inspector(isPresented: $showInspector) { inspector }
            .confirmationDialog(
                "Forcer l’extinction de cette machine ?",
                isPresented: Binding(
                    get: { pendingPowerOff != nil },
                    set: { if !$0 { pendingPowerOff = nil } }
                ),
                presenting: pendingPowerOff
            ) { machine in
                Button("Forcer l’extinction de \(machine.name)", role: .destructive) {
                    Task { await perform(.powerOff, on: machine) }
                }
                .help(String(localized: "Forcer l’extinction de \(machine.name)"))
                Button("Annuler", role: .cancel) { }
                    .help("Annuler l’extinction forcée")
            } message: { machine in
                Text("La machine « \(machine.name) » sera arrêtée sans laisser son système d’exploitation se fermer proprement. Des données peuvent être perdues.")
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
            ModuleLoadingView("Chargement des machines virtuelles…")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredMachines.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "Aucune machine virtuelle" : "Aucun résultat",
                systemImage: "desktopcomputer",
                description: searchText.isEmpty
                    ? "Créez une machine dans Virtual Machine Manager pour la gérer ici."
                    : "Modifiez votre recherche et réessayez."
            )
            .accessibilityFocused($contentFocused)
        } else {
            List(filteredMachines, selection: $selection) { machine in
                machineRow(machine)
                    .tag(machine.id)
                    .contextMenu { machineActions(machine) }
            }
            .accessibilityLabel("Machines virtuelles")
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
                Label("Démarrer", systemImage: "play")
            }
            .disabled(selectedMachine?.canStart != true || selectedIsBusy)
            .help("Démarrer la machine virtuelle")
        }

        ToolbarItem {
            Button {
                guard let selectedMachine else { return }
                Task { await perform(.shutdown, on: selectedMachine) }
            } label: {
                Label("Arrêter proprement", systemImage: "stop")
            }
            .disabled(selectedMachine?.canStop != true || selectedIsBusy)
            .help("Demander un arrêt propre au système invité")
        }

        ToolbarItem {
            Menu {
                Button("Forcer l’extinction…", role: .destructive) {
                    pendingPowerOff = selectedMachine
                }
                .disabled(selectedMachine?.canStop != true || selectedIsBusy)
                .help("Forcer l’extinction de la machine virtuelle")
                Toggle("Actualisation automatique", isOn: $autoRefresh)
                    .help("Actualiser automatiquement les machines virtuelles")
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
            .help("Autres actions")
        }

        ToolbarItem {
            Button {
                showInspector.toggle()
            } label: {
                Label("Informations", systemImage: "info.circle")
            }
            .disabled(selectedMachine == nil)
            .help(showInspector ? "Masquer les informations" : "Afficher les informations")
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .help("Actualiser les machines virtuelles")
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
                    if machine.vCPUCount > 0 { Text("\(machine.vCPUCount) processeurs virtuels") }
                    if let memory = memoryText(machine) { Text(memory) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if machine.isTransitioning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Opération en cours pour \(machine.name)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(machineAccessibilityLabel(machine))
        .accessibilityActions {
            if machine.canStart {
                Button("Démarrer") { Task { await perform(.powerOn, on: machine) } }
                    .help("Démarrer cette machine virtuelle")
            }
            if machine.canStop {
                Button("Arrêter proprement") { Task { await perform(.shutdown, on: machine) } }
                    .help("Arrêter proprement cette machine virtuelle")
                Button("Forcer l’extinction…", role: .destructive) {
                    pendingPowerOff = machine
                }
                .help("Forcer l’extinction de cette machine virtuelle")
            }
            Button("Lire les informations") {
                selection = machine.id
                showInspector = true
            }
            .help("Lire les informations de cette machine virtuelle")
        }
    }

    @ViewBuilder
    private func machineActions(_ machine: VirtualMachine) -> some View {
        if machine.canStart {
            Button("Démarrer") { Task { await perform(.powerOn, on: machine) } }
                .help("Démarrer cette machine virtuelle")
        }
        if machine.canStop {
            Button("Arrêter proprement") { Task { await perform(.shutdown, on: machine) } }
                .help("Arrêter proprement cette machine virtuelle")
            Divider()
            Button("Forcer l’extinction…", role: .destructive) { pendingPowerOff = machine }
                .help("Forcer l’extinction de cette machine virtuelle")
        }
        Divider()
        Button("Lire les informations") {
            selection = machine.id
            showInspector = true
        }
        .help("Lire les informations de cette machine virtuelle")
    }

    @ViewBuilder
    private var inspector: some View {
        if let machine = selectedMachine {
            Form {
                Section("Machine virtuelle") {
                    LabeledContent("Nom", value: machine.name)
                    LabeledContent("État", value: statusText(machine.status))
                    if let description = machine.description, !description.isEmpty {
                        LabeledContent("Description", value: description)
                    }
                    LabeledContent("Démarrage automatique", value: machine.autoRun ? "Oui" : "Non")
                }
                Section("Ressources") {
                    LabeledContent("Processeurs virtuels", value: machine.vCPUCount.formatted())
                    if let memory = memoryText(machine) { LabeledContent("Mémoire", value: memory) }
                    if let storageName = machine.storageName { LabeledContent("Stockage", value: storageName) }
                    LabeledContent("Disques", value: machine.virtualDisks.count.formatted())
                    LabeledContent("Interfaces réseau", value: machine.networkInterfaces.count.formatted())
                }
                if !machine.virtualDisks.isEmpty {
                    Section("Disques virtuels") {
                        ForEach(Array(machine.virtualDisks.enumerated()), id: \.offset) { index, disk in
                            LabeledContent(
                                disk.name ?? String(localized: "Disque \(index + 1)"),
                                value: disk.size?.formatted(.byteCount(style: .file)) ?? String(localized: "Taille inconnue")
                            )
                        }
                    }
                }
                if !machine.networkInterfaces.isEmpty {
                    Section("Réseau") {
                        ForEach(Array(machine.networkInterfaces.enumerated()), id: \.offset) { index, interface in
                            LabeledContent(
                                interface.networkName ?? String(localized: "Interface \(index + 1)"),
                                value: interface.macAddress ?? String(localized: "Adresse inconnue")
                            )
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            .accessibilityLabel("Informations sur \(machine.name)")
        } else {
            EmptyModuleView(
                title: "Aucune sélection",
                systemImage: "desktopcomputer",
                description: "Sélectionnez une machine virtuelle pour lire ses informations."
            )
        }
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.summary)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
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
            String(localized: "Chargement des machines virtuelles…"),
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
        if machine.vCPUCount > 0 { parts.append(String(localized: "\(machine.vCPUCount) processeurs virtuels")) }
        if let memory = memoryText(machine) { parts.append(memory) }
        return parts.formatted(.list(type: .and))
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "running": String(localized: "En fonctionnement")
        case "shutdown": String(localized: "Arrêtée")
        case "booting": String(localized: "Démarrage")
        case "shutting_down": String(localized: "Arrêt en cours")
        case "inaccessible": String(localized: "Inaccessible")
        case "moving": String(localized: "Déplacement")
        case "stor_migrating": String(localized: "Migration du stockage")
        case "creating": String(localized: "Création")
        case "importing": String(localized: "Importation")
        case "preparing": String(localized: "Préparation")
        case "ha_standby": String(localized: "Secours haute disponibilité")
        case "crashed": String(localized: "Arrêt inattendu")
        default: String(localized: "État inconnu")
        }
    }
}
