//
//  ContainersView.swift
//  dsmaccess
//
//  Gestion native des conteneurs et consultation de leurs journaux.
//

import SwiftUI

struct ContainersView: View {
    @State private var viewModel: ContainersViewModel
    @State private var selection: String?
    @State private var searchText = ""
    @State private var autoRefresh = true
    @State private var showInspector = false
    @AccessibilityFocusState private var contentFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: ContainersViewModel(session: session))
    }

    var body: some View {
        content
            .searchable(text: $searchText, prompt: "Rechercher un conteneur")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .task(id: autoRefresh) { await refreshPeriodically() }
            .inspector(isPresented: $showInspector) { inspector }
            .onChange(of: selection) {
                guard showInspector, let selectedContainer else { return }
                Task { await viewModel.loadLogs(for: selectedContainer) }
            }
            .onChange(of: viewModel.containers) {
                guard let selection else { return }
                if !viewModel.containers.contains(where: { $0.id == selection }) {
                    self.selection = nil
                    showInspector = false
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.containers.isEmpty {
            ModuleLoadingView("Chargement des conteneurs…")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredContainers.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "Aucun conteneur" : "Aucun résultat",
                systemImage: "shippingbox",
                description: searchText.isEmpty
                    ? "Créez un projet dans Container Manager pour gérer ses conteneurs ici."
                    : "Modifiez votre recherche et réessayez."
            )
            .accessibilityFocused($contentFocused)
        } else {
            List(filteredContainers, selection: $selection) { container in
                containerRow(container)
                    .tag(container.id)
                    .contextMenu { containerActions(container) }
            }
            .accessibilityLabel("Conteneurs")
            .accessibilityFocused($contentFocused)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                guard let selectedContainer else { return }
                Task { await perform(.start, on: selectedContainer) }
            } label: {
                Label("Démarrer", systemImage: "play")
            }
            .disabled(selectedContainer?.isRunning != false || selectedIsBusy)
            .help("Démarrer le conteneur")
        }

        ToolbarItem {
            Button {
                guard let selectedContainer else { return }
                Task { await perform(.stop, on: selectedContainer) }
            } label: {
                Label("Arrêter", systemImage: "stop")
            }
            .disabled(selectedContainer?.isRunning != true || selectedIsBusy)
            .help("Arrêter le conteneur")
        }

        ToolbarItem {
            Button {
                guard let selectedContainer else { return }
                Task { await perform(.restart, on: selectedContainer) }
            } label: {
                Label("Redémarrer", systemImage: "arrow.clockwise.circle")
            }
            .disabled(selectedContainer?.isRunning != true || selectedIsBusy)
            .help("Redémarrer le conteneur")
        }

        ToolbarItem {
            Button {
                showInspector.toggle()
                if showInspector, let selectedContainer {
                    Task { await viewModel.loadLogs(for: selectedContainer) }
                }
            } label: {
                Label("Informations et journaux", systemImage: "info.circle")
            }
            .disabled(selectedContainer == nil)
            .help(showInspector ? "Masquer les informations" : "Afficher les informations et journaux")
        }

        ToolbarItem {
            Menu {
                Toggle("Actualisation automatique", isOn: $autoRefresh)
                    .help("Actualiser automatiquement les conteneurs")
            } label: {
                Label("Options d’actualisation", systemImage: "ellipsis.circle")
            }
            .help("Options d’actualisation")
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .help("Actualiser les conteneurs")
        }
    }

    private func containerRow(_ container: ContainerItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(container.isRunning ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(container.name).fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(container.isRunning ? "En fonctionnement" : "Arrêté")
                    if let image = container.image, !image.isEmpty { Text(image) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let cpu = container.cpuPercent, container.isRunning {
                Text("Processeur \(cpu.formatted(.number.precision(.fractionLength(1)))) %")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(containerAccessibilityLabel(container))
        .accessibilityActions {
            Button(container.isRunning ? "Arrêter" : "Démarrer") {
                Task { await perform(container.isRunning ? .stop : .start, on: container) }
            }
            .help(container.isRunning ? "Arrêter le conteneur" : "Démarrer le conteneur")
            if container.isRunning {
                Button("Redémarrer") { Task { await perform(.restart, on: container) } }
                    .help("Redémarrer le conteneur")
            }
            Button("Informations et journaux") {
                selection = container.id
                showInspector = true
                Task { await viewModel.loadLogs(for: container) }
            }
            .help("Afficher les informations et journaux du conteneur")
        }
    }

    @ViewBuilder
    private func containerActions(_ container: ContainerItem) -> some View {
        if container.isRunning {
            Button("Arrêter") { Task { await perform(.stop, on: container) } }
                .help("Arrêter le conteneur")
            Button("Redémarrer") { Task { await perform(.restart, on: container) } }
                .help("Redémarrer le conteneur")
        } else {
            Button("Démarrer") { Task { await perform(.start, on: container) } }
                .help("Démarrer le conteneur")
        }
        Divider()
        Button("Informations et journaux") {
            selection = container.id
            showInspector = true
            Task { await viewModel.loadLogs(for: container) }
        }
        .help("Afficher les informations et journaux du conteneur")
    }

    @ViewBuilder
    private var inspector: some View {
        if let container = selectedContainer {
            TabView {
                Form {
                    Section("Conteneur") {
                        LabeledContent("Nom", value: container.name)
                        LabeledContent("État", value: container.isRunning ? "En fonctionnement" : "Arrêté")
                        if let image = container.image { LabeledContent("Image", value: image) }
                        LabeledContent("Redémarrage automatique", value: container.autoRestart ? "Oui" : "Non")
                    }
                    Section("Ressources") {
                        if let cpu = container.cpuPercent {
                            LabeledContent(
                                "Processeur",
                                value: "\(cpu.formatted(.number.precision(.fractionLength(1)))) %"
                            )
                        }
                        if let memory = container.memoryBytes {
                            LabeledContent("Mémoire", value: memory.formatted(.byteCount(style: .memory)))
                        }
                        if let started = dateText(container.startedAt) {
                            LabeledContent("Démarré", value: started)
                        }
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("Informations", systemImage: "info.circle") }

                logView(container)
                    .tabItem { Label("Journal", systemImage: "text.alignleft") }
            }
            .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
            .accessibilityLabel("Informations et journaux de \(container.name)")
        } else {
            EmptyModuleView(
                title: "Aucune sélection",
                systemImage: "shippingbox",
                description: "Sélectionnez un conteneur pour lire ses informations."
            )
        }
    }

    @ViewBuilder
    private func logView(_ container: ContainerItem) -> some View {
        if viewModel.isLoadingLogs && viewModel.logsContainerName == container.name {
            ModuleLoadingView("Chargement du journal…")
        } else if let message = viewModel.logErrorMessage {
            ModuleErrorView(message: message) {
                Task { await viewModel.loadLogs(for: container) }
            }
        } else if viewModel.logs.isEmpty || viewModel.logsContainerName != container.name {
            EmptyModuleView(
                title: "Journal vide",
                systemImage: "text.alignleft",
                description: "Ce conteneur n’a produit aucune ligne de journal disponible."
            )
        } else {
            List(viewModel.logs) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    if let metadata = logMetadata(entry) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.message)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(logAccessibilityLabel(entry))
            }
            .accessibilityLabel("Journal de \(container.name)")
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

    private var filteredContainers: [ContainerItem] {
        guard !searchText.isEmpty else { return viewModel.containers }
        return viewModel.containers.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.status.localizedStandardContains(searchText)
                || ($0.image?.localizedStandardContains(searchText) == true)
        }
    }

    private var selectedContainer: ContainerItem? {
        viewModel.containers.first { $0.id == selection }
    }

    private var selectedIsBusy: Bool {
        guard let selectedContainer else { return false }
        return viewModel.busyNames.contains(selectedContainer.name)
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "Chargement des conteneurs…"),
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

    private func perform(_ action: ContainerAction, on container: ContainerItem) async {
        VoiceOver.announce(await viewModel.perform(action, on: container), priority: .high)
    }

    private func containerAccessibilityLabel(_ container: ContainerItem) -> String {
        var parts = [container.name, container.isRunning ? String(localized: "en fonctionnement") : String(localized: "arrêté")]
        if let image = container.image { parts.append(String(localized: "image \(image)")) }
        if let cpu = container.cpuPercent { parts.append(String(localized: "processeur \(cpu.formatted()) pour cent")) }
        if let memory = container.memoryBytes { parts.append(memory.formatted(.byteCount(style: .memory))) }
        return parts.formatted(.list(type: .and))
    }

    private func dateText(_ timestamp: Int64?) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func logMetadata(_ entry: ContainerLogEntry) -> String? {
        [dateText(entry.timestamp), entry.stream].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    private func logAccessibilityLabel(_ entry: ContainerLogEntry) -> String {
        [dateText(entry.timestamp), entry.stream, entry.message]
            .compactMap { $0 }
            .formatted(.list(type: .and))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
