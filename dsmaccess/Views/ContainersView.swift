//
//  ContainersView.swift
//  dsmaccess
//
//  Containers module: containers, compose projects, images and networks of
//  Container Manager, one tab each as in DSM.
//

import SwiftUI

struct ContainersView: View {
    /// Container Manager's own sections, minus those its package does not expose here.
    private enum Pane: String, CaseIterable, Identifiable {
        case containers
        case projects
        case images
        case registries
        case networks
        case log

        var id: Self { self }
    }

    @State private var pane = Pane.containers
    @State private var projects: DockerProjectsViewModel
    @State private var images: DockerImagesViewModel
    @State private var registries: DockerRegistriesViewModel
    @State private var networks: DockerNetworksViewModel
    @State private var log: DockerLogViewModel
    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _projects = State(initialValue: DockerProjectsViewModel(session: session))
        _images = State(initialValue: DockerImagesViewModel(session: session))
        _registries = State(initialValue: DockerRegistriesViewModel(session: session))
        _networks = State(initialValue: DockerNetworksViewModel(session: session))
        _log = State(initialValue: DockerLogViewModel(session: session))
    }

    var body: some View {
        // A TabView and not a segmented picker, for the same reason as the resource monitor:
        // tabs announce themselves as tabs. Wrapped in a VStack so they stay in the content.
        VStack(spacing: 0) {
            TabView(selection: $pane) {
                ContainersPaneView(session: session, isActive: pane == .containers)
                    .tabItem { Text("containers.tab.containers") }
                    .tag(Pane.containers)
                if session.capabilities.supports("SYNO.Docker.Project") {
                    DockerProjectsView(vm: projects)
                        .tabItem { Text("containers.tab.projects") }
                        .tag(Pane.projects)
                }
                if session.capabilities.supports("SYNO.Docker.Image") {
                    DockerImagesView(vm: images)
                        .tabItem { Text("containers.tab.images") }
                        .tag(Pane.images)
                }
                if session.capabilities.supports("SYNO.Docker.Registry") {
                    DockerRegistriesView(vm: registries, images: images)
                        .tabItem { Text("containers.tab.registries") }
                        .tag(Pane.registries)
                }
                if session.capabilities.supports("SYNO.Docker.Network") {
                    DockerNetworksView(vm: networks)
                        .tabItem { Text("containers.tab.networks") }
                        .tag(Pane.networks)
                }
                if session.capabilities.supports("SYNO.Docker.Log") {
                    DockerLogView(vm: log, isActive: pane == .log)
                        .tabItem { Text("common.label.log") }
                        .tag(Pane.log)
                }
            }
        }
    }
}

/// The historical containers list, unchanged in behaviour, now the first tab of the module.
struct ContainersPaneView: View {
    private enum DetailsSection: Hashable {
        case information
        case statistics
        case logs
        case processes
    }

    @State private var viewModel: ContainersViewModel
    @State private var selection: String?
    @State private var order = [KeyPathComparator(\ContainerItem.name)]
    @State private var searchText = ""
    @State private var autoRefresh = true
    @State private var detailsContainer: ContainerItem?
    @State private var detailsSection = DetailsSection.information
    @State private var pendingDelete: ContainerItem?
    @State private var pendingForceStop: ContainerItem?
    @State private var pendingReset: ContainerItem?
    @State private var exportingProfileOf: ContainerItem?
    @State private var editingSettingsOf: ContainerItem?
    @State private var duplicating: ContainerItem?
    @State private var duplicateName = ""
    @State private var showsCreation = false
    @State private var exportShareNames: [String] = []
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var detailsSectionFocused: Bool
    /// Whether this tab is the selected one. Its search field and toolbar live at the window
    /// level: left unconditioned, they linger — disabled but reachable — over the other tabs.
    private let isActive: Bool

    init(session: SessionStore, isActive: Bool) {
        _viewModel = State(initialValue: ContainersViewModel(session: session))
        self.isActive = isActive
    }

    var body: some View {
        searchableContent
            .toolbar { if isActive { toolbar } }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .task(id: autoRefresh) { await refreshPeriodically() }
            .sheet(item: $detailsContainer, content: detailsSheet)
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("common.button.delete", role: .destructive) {
                    guard let container = pendingDelete else { return }
                    pendingDelete = nil
                    Task { VoiceOver.announce(await viewModel.delete(container), priority: .high) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                if let container = pendingDelete {
                    Text(String(
                        localized: "containers.delete.confirm.message",
                        defaultValue: "The container “\(container.name)” will be stopped if needed, then removed with its settings. Data in mounted folders stays on the NAS. This cannot be undone."
                    ))
                }
            }
            .confirmationDialog(
                forceStopTitle,
                isPresented: Binding(
                    get: { pendingForceStop != nil },
                    set: { if !$0 { pendingForceStop = nil } }
                )
            ) {
                Button("containers.action.force_stop", role: .destructive) {
                    guard let container = pendingForceStop else { return }
                    pendingForceStop = nil
                    Task { VoiceOver.announce(await viewModel.forceStop(container), priority: .high) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                if let container = pendingForceStop {
                    Text(String(
                        localized: "containers.force_stop.confirm.message",
                        defaultValue: "“\(container.name)” will be killed at once, without being given time to finish what it is doing. Unsaved work inside the container is lost."
                    ))
                }
            }
            .confirmationDialog(
                resetTitle,
                isPresented: Binding(
                    get: { pendingReset != nil },
                    set: { if !$0 { pendingReset = nil } }
                )
            ) {
                Button("containers.action.reset", role: .destructive) {
                    guard let container = pendingReset else { return }
                    pendingReset = nil
                    Task { VoiceOver.announce(await viewModel.reset(container), priority: .high) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                if let container = pendingReset {
                    Text(String(
                        localized: "containers.reset.confirm.message",
                        defaultValue: "“\(container.name)” will be recreated from its settings and left stopped. Its writable layer is discarded: anything written inside the container, outside a mounted folder, is lost. This cannot be undone."
                    ))
                }
            }
            .sheet(item: $editingSettingsOf) { container in
                ContainerSettingsSheet(container: container, vm: viewModel)
            }
            .sheet(isPresented: $showsCreation) {
                ContainerCreationSheet(vm: viewModel)
            }
            .alert(
                duplicateTitle,
                isPresented: Binding(
                    get: { duplicating != nil },
                    set: { if !$0 { duplicating = nil } }
                )
            ) {
                TextField("containers.column.name", text: $duplicateName)
                Button("containers.duplicate.action") {
                    guard let container = duplicating else { return }
                    let name = duplicateName.trimmingCharacters(in: .whitespacesAndNewlines)
                    duplicating = nil
                    guard !name.isEmpty else { return }
                    Task {
                        VoiceOver.announce(
                            await viewModel.duplicate(container, as: name),
                            priority: .high
                        )
                    }
                }
                Button("common.button.cancel", role: .cancel) { duplicating = nil }
            } message: {
                Text("containers.duplicate.message")
            }
            .onChange(of: duplicating) { _, container in
                // A suggested name saves typing, and makes plain that the copy is a new
                // container rather than a second name for the same one.
                guard let container else { return }
                duplicateName = String(
                    localized: "containers.duplicate.suggested_name",
                    defaultValue: "\(container.name)-copy"
                )
            }
            .sheet(item: $exportingProfileOf) { container in
                // DSM names the file itself, so choosing the folder is the whole decision.
                SharedFolderPickerSheet(
                    initialPath: "/docker",
                    shareNames: exportShareNames,
                    loadFolders: viewModel.folders,
                    createFolder: nil
                ) { chosen in
                    Task {
                        VoiceOver.announce(
                            await viewModel.exportProfile(of: container, to: chosen),
                            priority: .high
                        )
                    }
                }
            }
            .task { exportShareNames = (try? await viewModel.shareNames()) ?? [] }
            .onChange(of: viewModel.containers) {
                guard let selection else { return }
                if !viewModel.containers.contains(where: { $0.id == selection }) {
                    self.selection = nil
                    detailsContainer = nil
                }
            }
    }

    @ViewBuilder
    private var searchableContent: some View {
        if isActive {
            content.searchable(text: $searchText, prompt: "containers.search.prompt")
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.containers.isEmpty {
            ModuleLoadingView("containers.loading")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredContainers.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "containers.empty.title" : "common.empty.results",
                systemImage: "shippingbox",
                description: searchText.isEmpty
                    ? "containers.empty.description"
                    : "common.empty.results.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            Table(
                filteredContainers.sorted(using: order),
                selection: $selection,
                sortOrder: $order
            ) {
                TableColumn("containers.column.name", value: \.name)
                TableColumn("common.column.state", value: \.sortableState) { container in
                    Text(container.isRunning ? "common.status.running" : "common.status.stopped")
                }
                TableColumn("containers.column.image", value: \.sortableImage) { container in
                    Text(container.image ?? "—")
                }
                TableColumn("containers.column.processor", value: \.sortableCPU) { container in
                    Text(cpuText(container))
                }
                TableColumn("containers.column.memory", value: \.sortableMemory) { container in
                    Text(container.memoryBytes?.formatted(.byteCount(style: .memory)) ?? "—")
                }
            }
            .accessibilityLabel("common.module.containers")
            .accessibilityFocused($contentFocused)
            .contextMenu(forSelectionType: ContainerItem.ID.self) { ids in
                if let container = viewModel.containers.first(where: { ids.contains($0.id) }) {
                    containerActions(container)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                guard let selectedContainer else { return }
                Task { await perform(.start, on: selectedContainer) }
            } label: {
                Label("common.button.start", systemImage: "play")
            }
            .disabled(selectedContainer?.isRunning != false || selectedIsBusy)
            .help("containers.action.start.hint")
        }

        ToolbarItem {
            Button {
                guard let selectedContainer else { return }
                Task { await perform(.stop, on: selectedContainer) }
            } label: {
                Label("common.button.stop", systemImage: "stop")
            }
            .disabled(selectedContainer?.isRunning != true || selectedIsBusy)
            .help("containers.action.stop.hint")
        }

        ToolbarItem {
            Button {
                guard let selectedContainer else { return }
                Task { await perform(.restart, on: selectedContainer) }
            } label: {
                Label("containers.action.restart", systemImage: "arrow.clockwise.circle")
            }
            .disabled(selectedContainer?.isRunning != true || selectedIsBusy)
            .help("containers.action.restart.hint")
        }

        ToolbarItem {
            Button {
                guard let selectedContainer else { return }
                presentDetails(for: selectedContainer)
            } label: {
                Label("containers.detail.title", systemImage: "info.circle")
            }
            .disabled(selectedContainer == nil)
            .help("containers.action.show_details")
        }

        ToolbarItem {
            Menu {
                Toggle("common.label.automatic_refresh", isOn: $autoRefresh)
                    .help("containers.toolbar.auto_refresh")
            } label: {
                Label("common.label.refresh_options", systemImage: "ellipsis.circle")
            }
            .help("common.label.refresh_options")
        }

        ToolbarItem {
            Button {
                showsCreation = true
            } label: {
                Label("containers.create.title", systemImage: "plus")
            }
            .help("containers.create.hint")
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("common.button.refresh", systemImage: "arrow.clockwise")
            }
            .help("containers.toolbar.refresh")
        }
    }

    private var duplicateTitle: Text {
        Text(String(
            localized: "containers.duplicate.title",
            defaultValue: "Duplicate “\(duplicating?.name ?? "")”?"
        ))
    }

    /// A stopped container reports no usage; the dash says so rather than showing 0 %.
    private func cpuText(_ container: ContainerItem) -> String {
        guard container.isRunning, let cpu = container.cpuPercent else { return "—" }
        return cpu.formatted(.percent.precision(.fractionLength(1)).scale(1))
    }

    @ViewBuilder
    private func containerActions(_ container: ContainerItem) -> some View {
        if container.isRunning {
            Button("common.button.stop") { Task { await perform(.stop, on: container) } }
                .help("containers.action.stop.hint")
            Button("containers.action.force_stop") { pendingForceStop = container }
                .help("containers.action.force_stop.hint")
            Button("containers.action.restart") { Task { await perform(.restart, on: container) } }
                .help("containers.action.restart.hint")
        } else {
            Button("common.button.start") { Task { await perform(.start, on: container) } }
                .help("containers.action.start.hint")
        }
        Divider()
        Button("containers.action.reset", role: .destructive) { pendingReset = container }
            .help("containers.action.reset.hint")
        Button("common.button.delete", role: .destructive) { pendingDelete = container }
            .help("containers.action.delete.hint")
        Divider()
        Button("containers.duplicate.action") { duplicating = container }
            .help("containers.duplicate.hint")
        Button("containers.settings.title") { editingSettingsOf = container }
            .help("containers.settings.hint")
        Button("containers.action.export_profile") { exportingProfileOf = container }
            .help("containers.action.export_profile.hint")
        Button("containers.detail.title") {
            presentDetails(for: container)
        }
        .help("containers.action.show_details.hint")
    }

    private var deleteTitle: Text {
        Text(String(
            localized: "containers.delete.confirm.title",
            defaultValue: "Delete “\(pendingDelete?.name ?? "")”?"
        ))
    }

    private var forceStopTitle: Text {
        Text(String(
            localized: "containers.force_stop.confirm.title",
            defaultValue: "Force stop “\(pendingForceStop?.name ?? "")”?"
        ))
    }

    private var resetTitle: Text {
        Text(String(
            localized: "containers.reset.confirm.title",
            defaultValue: "Reset “\(pendingReset?.name ?? "")”?"
        ))
    }

    private func detailsSheet(_ container: ContainerItem) -> some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("containers.detail.title", selection: $detailsSection) {
                    Text("common.label.information").tag(DetailsSection.information)
                    Text("containers.detail.statistics").tag(DetailsSection.statistics)
                    Text("common.label.log").tag(DetailsSection.logs)
                    Text("containers.detail.processes").tag(DetailsSection.processes)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()
                .accessibilityFocused($detailsSectionFocused)

                Divider()

                if detailsSection == .processes {
                    processView(container)
                } else if detailsSection == .statistics {
                    statisticsView(container)
                } else if detailsSection == .information {
                    Form {
                        Section("containers.column.name") {
                            LabeledContent("common.column.name", value: container.name)
                            LabeledContent("common.column.state", value: container.isRunning ? String(localized: "common.status.running") : String(localized: "common.status.stopped"))
                            if let image = container.image { LabeledContent("common.label.image", value: image) }
                            LabeledContent("containers.detail.auto_restart", value: container.autoRestart ? String(localized: "common.answer.yes") : String(localized: "common.answer.no"))
                        }
                        if hasResourceInformation(container) {
                            Section("common.label.resources") {
                                if let cpu = container.cpuPercent {
                                    LabeledContent(
                                        "common.metric.processor",
                                        value: "\(cpu.formatted(.number.precision(.fractionLength(1)))) %"
                                    )
                                }
                                if let memory = container.memoryBytes {
                                    LabeledContent("common.metric.memory", value: memory.formatted(.byteCount(style: .memory)))
                                }
                                if let uptime = uptimeText(container.uptimeSeconds) {
                                    LabeledContent("common.label.uptime", value: uptime)
                                } else if let started = dateText(container.startedAt) {
                                    LabeledContent("containers.status.started", value: started)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .accessibilityLabel("containers.detail.information.label")
                } else {
                    logView(container)
                }
            }
            .accessibilityLabel(String(localized: "containers.detail.title_named", defaultValue: "Details for \(container.name)"))
            .navigationTitle(String(localized: "containers.detail.title_named", defaultValue: "Details for \(container.name)"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.status.done") { detailsContainer = nil }
                        .keyboardShortcut(.defaultAction)
                        .help("common.button.close_information")
                }
            }
        }
        .frame(minWidth: 520, minHeight: 430)
        .task { await focusDetails(for: container) }
        .onDisappear { detailsSectionFocused = false }
    }

    @ViewBuilder
    private func statisticsView(_ container: ContainerItem) -> some View {
        if viewModel.isLoadingStatistics && viewModel.statisticsContainerName == container.name {
            ModuleLoadingView("containers.statistics.loading")
        } else if let message = viewModel.statisticsErrorMessage {
            ModuleErrorView(message: message) {
                Task { await viewModel.loadStatistics(for: container) }
            }
        } else if let statistics = viewModel.statistics,
                  viewModel.statisticsContainerName == container.name {
            Form {
                Section("common.label.resources") {
                    // Docker sends counters, not a percentage: a container just started has no
                    // earlier sample to compare with, and says so instead of showing 0 %.
                    LabeledContent(
                        "common.metric.processor",
                        value: statistics.cpuPercent.map {
                            "\($0.formatted(.number.precision(.fractionLength(1)))) %"
                        } ?? String(localized: "containers.statistics.pending")
                    )
                    LabeledContent(
                        "common.metric.memory",
                        value: statistics.memoryUsage.formatted(.byteCount(style: .memory))
                    )
                    if let share = statistics.memoryPercent {
                        LabeledContent(
                            "containers.statistics.memory_share",
                            value: "\(share.formatted(.number.precision(.fractionLength(1)))) %"
                        )
                    }
                    if statistics.memoryLimit > 0 {
                        LabeledContent(
                            "containers.statistics.memory_limit",
                            value: statistics.memoryLimit.formatted(.byteCount(style: .memory))
                        )
                    }
                }
                Section("containers.statistics.network") {
                    LabeledContent(
                        "containers.statistics.received",
                        value: statistics.receivedBytes.formatted(.byteCount(style: .file))
                    )
                    LabeledContent(
                        "containers.statistics.sent",
                        value: statistics.sentBytes.formatted(.byteCount(style: .file))
                    )
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel(String(
                localized: "containers.statistics.label",
                defaultValue: "Statistics of \(container.name)"
            ))
            .labeledContentStyle(.readable)
        } else {
            EmptyModuleView(
                title: "containers.statistics.empty.title",
                systemImage: "chart.bar",
                description: "containers.statistics.empty.description"
            )
        }
    }

    @ViewBuilder
    private func processView(_ container: ContainerItem) -> some View {
        if viewModel.isLoadingProcesses && viewModel.processesContainerName == container.name {
            ModuleLoadingView("containers.detail.processes.loading")
        } else if let message = viewModel.processErrorMessage {
            ModuleErrorView(message: message) {
                Task { await viewModel.loadProcesses(for: container) }
            }
        } else if viewModel.processes.isEmpty || viewModel.processesContainerName != container.name {
            EmptyModuleView(
                title: "containers.detail.processes.empty.title",
                systemImage: "gearshape.2",
                description: "containers.detail.processes.empty.description"
            )
        } else {
            Table(viewModel.processes) {
                TableColumn("containers.detail.processes.column.pid") { process in
                    Text(process.pid)
                }
                TableColumn("common.metric.processor") { process in
                    Text(process.cpuPercent.map {
                        "\($0.formatted(.number.precision(.fractionLength(1)))) %"
                    } ?? "—")
                }
                TableColumn("common.metric.memory") { process in
                    Text(process.memoryBytes?.formatted(.byteCount(style: .memory)) ?? "—")
                }
                TableColumn("containers.detail.processes.column.command") { process in
                    Text(process.command)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .accessibilityLabel(String(
                localized: "containers.detail.processes.table_label",
                defaultValue: "Processes of \(container.name)"
            ))
        }
    }

    @ViewBuilder
    private func logView(_ container: ContainerItem) -> some View {
        if viewModel.isLoadingLogs && viewModel.logsContainerName == container.name {
            ModuleLoadingView("common.status.loading_log")
        } else if let message = viewModel.logErrorMessage {
            ModuleErrorView(message: message) {
                Task { await viewModel.loadLogs(for: container) }
            }
        } else if viewModel.logs.isEmpty || viewModel.logsContainerName != container.name {
            EmptyModuleView(
                title: "containers.log.empty.title",
                systemImage: "text.alignleft",
                description: "containers.log.empty.description"
            )
        } else {
            List(viewModel.logs) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    if let metadata = logMetadata(entry) {
                        Text(metadata)
                            .font(.caption)
                            .foregroundStyle(.readableSecondary)
                    }
                    Text(entry.message)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(logAccessibilityLabel(entry))
            }
            .accessibilityLabel(String(localized: "containers.log.title_named", defaultValue: "Log for \(container.name)"))
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
            String(localized: "containers.loading"),
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

    private func presentDetails(for container: ContainerItem) {
        selection = container.id
        detailsSection = .information
        detailsContainer = container
        Task { await viewModel.loadLogs(for: container) }
        Task { await viewModel.loadProcesses(for: container) }
        Task { await viewModel.loadStatistics(for: container) }
    }

    private func focusDetails(for container: ContainerItem) async {
        await Task.yield()
        guard detailsContainer?.id == container.id else { return }
        detailsSectionFocused = true
        VoiceOver.announce(
            String(localized: "containers.detail.title_named", defaultValue: "Details for \(container.name)"),
            category: .navigation
        )
    }

    private func dateText(_ timestamp: String?) -> String? {
        guard let timestamp, !timestamp.isEmpty else { return nil }
        if let seconds = TimeInterval(timestamp) {
            return Date(timeIntervalSince1970: seconds)
                .formatted(date: .abbreviated, time: .shortened)
        }
        if let date = try? Date(timestamp, strategy: .iso8601) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return timestamp
    }

    private func uptimeText(_ seconds: Int64?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        return Duration.seconds(seconds).formatted(
            .units(
                allowed: [.days, .hours, .minutes, .seconds],
                width: .wide,
                maximumUnitCount: 2
            )
        )
    }

    private func hasResourceInformation(_ container: ContainerItem) -> Bool {
        container.cpuPercent != nil
            || container.memoryBytes != nil
            || container.uptimeSeconds != nil
            || container.startedAt != nil
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
