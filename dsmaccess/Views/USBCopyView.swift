//
//  USBCopyView.swift
//  dsmaccess
//
//  Native, accessible management of USB Copy tasks.
//

import SwiftUI

struct USBCopyView: View {
    @State private var viewModel: USBCopyViewModel
    @State private var selection: Int?
    @State private var order = [KeyPathComparator(\USBCopyTask.name, order: .forward)]
    @State private var searchText = ""
    @State private var presentedSheet: USBCopyPresentedSheet?
    @State private var pendingDeletion: USBCopyTask?
    @State private var pendingHighImpactRun: USBCopyTask?
    @AccessibilityFocusState private var contentFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: USBCopyViewModel(session: session))
    }

    var body: some View {
        content
            .searchable(text: $searchText, prompt: "usb_copy.list.search.label")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .task(id: activeTaskIDs) { await refreshActiveTasks() }
            .sheet(item: $presentedSheet) { sheet in
                sheetContent(sheet)
            }
            .confirmationDialog(
                "usb_copy.list.delete_task.confirm.title",
                isPresented: deletionPresented
            ) {
                Button("usb_copy.list.delete_task.button", role: .destructive) {
                    if let task = pendingDeletion {
                        Task { await announce(viewModel.delete(task)) }
                    }
                    pendingDeletion = nil
                }
                Button("common.button.cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                if let task = pendingDeletion {
                    Text(String(localized: "usb_copy.list.delete_task.confirm.description", defaultValue: "The “\(task.name)” task will be permanently removed from USB Copy. This action cannot be undone. Make sure you no longer need its configuration or history."))
                }
            }
            .confirmationDialog(
                "usb_copy.list.run_task.confirm.title",
                isPresented: highImpactRunPresented
            ) {
                Button("usb_copy.list.run_task.button", role: .destructive) {
                    if let task = pendingHighImpactRun {
                        Task { await announce(viewModel.run(task)) }
                    }
                    pendingHighImpactRun = nil
                }
                Button("common.button.cancel", role: .cancel) { pendingHighImpactRun = nil }
            } message: {
                if let task = pendingHighImpactRun {
                    if task.knownStrategy == .mirror {
                        Text(String(localized: "usb_copy.list.run_task.confirm.mirror.description", defaultValue: "The “\(task.name)” task will delete files from the destination when they are no longer present at the source."))
                    } else {
                        Text(String(localized: "usb_copy.list.run_task.confirm.delete_source.description", defaultValue: "The “\(task.name)” task will delete source files after copying them to the destination."))
                    }
                }
            }
            .onChange(of: viewModel.tasks) {
                if let selection, !viewModel.tasks.contains(where: { $0.id == selection }) {
                    self.selection = nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            ModuleLoadingView("usb_copy.list.loading")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage, viewModel.tasks.isEmpty {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredTasks.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "usb_copy.list.empty.title" : "common.empty.results",
                systemImage: "externaldrive.badge.arrowtriangle.2.circlepath",
                description: searchText.isEmpty
                    ? "usb_copy.list.empty.description"
                    : "common.empty.results.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            Table(filteredTasks.sorted(using: order), selection: $selection, sortOrder: $order) {
                TableColumn("common.column.name", value: \.name) { task in
                    Text(task.name)
                }
                TableColumn("common.column.kind", value: \.sortableType) { task in
                    Text(task.typeDescription)
                }
                TableColumn("common.column.state", value: \.sortableStatus) { task in
                    Text(task.statusDescription)
                }
                TableColumn("common.column.source", value: \.sourcePath) { task in
                    Text(task.sourcePath)
                }
                TableColumn("common.column.destination", value: \.destinationPath) { task in
                    Text(task.destinationPath)
                }
                TableColumn("common.column.strategy", value: \.sortableStrategy) { task in
                    Text(task.strategyDescription)
                }
                TableColumn("common.column.last_run", value: \.sortableFinishTime) { task in
                    Text(lastRunText(task))
                }
            }
            .accessibilityLabel("usb_copy.list.title")
            .accessibilityFocused($contentFocused)
            .contextMenu(forSelectionType: Int.self) { ids in
                if let task = viewModel.tasks.first(where: { ids.contains($0.id) }) {
                    contextMenu(for: task)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button("usb_copy.list.create_task.button", systemImage: "plus") {
                presentedSheet = .create
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("common.action.create_usb_copy_task")
        }

        ToolbarItem {
            if selectedTask?.canCancel == true {
                Button("usb_copy.list.cancel_copy.button", systemImage: "stop.fill") {
                    if let task = selectedTask { Task { await announce(viewModel.cancel(task)) } }
                }
                .disabled(selectedTaskIsBusy)
                .help("usb_copy.list.stop_task.hint")
            } else {
                Button("usb_copy.list.run.button", systemImage: "play.fill") {
                    if let task = selectedTask { requestRun(task) }
                }
                .disabled(selectedTask?.canRun != true || selectedTaskIsBusy)
                .help("usb_copy.list.run_task.hint")
            }
        }

        ToolbarItem {
            Menu("usb_copy.list.edit_task.button", systemImage: "slider.horizontal.3") {
                Button("usb_copy.list.task_settings.menu") { presentSelected(.edit) }
                Button("usb_copy.list.trigger.menu") { presentSelected(.trigger) }
                Button("usb_copy.list.file_filter.menu") { presentSelected(.filter) }
            }
            .disabled(selectedTask == nil || selectedTask?.isActive == true || selectedTaskIsBusy)
            .help(
                selectedTask?.isActive == true
                    ? "usb_copy.list.edit_task.busy.hint"
                    : "usb_copy.list.edit_task.hint"
            )
        }

        ToolbarItem {
            Menu("usb_copy.list.column.status", systemImage: "power") {
                if selectedTask?.canEnable == true {
                    Button("common.button.enable") {
                        if let task = selectedTask { requestEnable(task) }
                    }
                } else if selectedTask?.canDisable == true {
                    Button("common.button.disable") {
                        if let task = selectedTask { Task { await announce(viewModel.disable(task)) } }
                    }
                }
            }
            .disabled(selectedTask?.canToggleEnabled != true || selectedTaskIsBusy)
            .help("usb_copy.list.toggle_task.hint")
        }

        ToolbarItem {
            Button(role: .destructive) {
                pendingDeletion = selectedTask
            } label: {
                Label("usb_copy.list.delete_task.button", systemImage: "trash")
            }
            .disabled(selectedTask?.canDelete != true || selectedTaskIsBusy)
            .help("usb_copy.list.delete_task.hint")
        }

        ToolbarItem {
            Menu("common.button.more_options", systemImage: "ellipsis.circle") {
                Button("usb_copy.list.log.menu", systemImage: "list.bullet.rectangle") {
                    presentedSheet = .logs
                }
                Button("usb_copy.list.global_settings.menu", systemImage: "gearshape") {
                    presentedSheet = .globalSettings
                }
            }
            .help("usb_copy.list.more_menu.hint")
        }

        ToolbarItem {
            Button("common.button.refresh", systemImage: "arrow.clockwise") {
                Task { await load() }
            }
            .help("usb_copy.list.refresh.hint")
        }
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.summary)
            Spacer()
            if let selectedTask {
                Text(selectedTaskStatus(selectedTask))
            }
        }
        .font(.caption)
        .foregroundStyle(.readableSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var filteredTasks: [USBCopyTask] {
        guard !searchText.isEmpty else { return viewModel.tasks }
        return viewModel.tasks.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.sourcePath.localizedStandardContains(searchText)
                || $0.destinationPath.localizedStandardContains(searchText)
                || selectedTaskStatus($0).localizedStandardContains(searchText)
        }
    }

    private var selectedTask: USBCopyTask? {
        guard let selection else { return nil }
        return viewModel.tasks.first { $0.id == selection }
    }

    private var selectedTaskIsBusy: Bool {
        guard let selection else { return false }
        return viewModel.busyTaskIDs.contains(selection)
    }

    private var activeTaskIDs: Set<Int> {
        Set(viewModel.tasks.filter(\.isActive).map(\.id))
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var highImpactRunPresented: Binding<Bool> {
        Binding(
            get: { pendingHighImpactRun != nil },
            set: { if !$0 { pendingHighImpactRun = nil } }
        )
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "usb_copy.list.loading"),
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

    private func refreshActiveTasks() async {
        guard !activeTaskIDs.isEmpty else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await viewModel.load(silently: true)
        }
    }

    private func presentSelected(_ destination: USBCopyTaskSheetDestination) {
        guard let task = selectedTask else { return }
        switch destination {
        case .edit: presentedSheet = .edit(task.id)
        case .trigger: presentedSheet = .trigger(task.id)
        case .filter: presentedSheet = .filter(task.id)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: USBCopyPresentedSheet) -> some View {
        switch sheet {
        case .create:
            USBCopyTaskEditorSheet(
                localShares: viewModel.localShares,
                externalShares: viewModel.externalShares,
                loadFolders: viewModel.folders,
                onCreate: viewModel.create
            )
        case .edit(let taskID):
            USBCopyTaskDetailsSheet(
                taskID: taskID,
                destination: .edit,
                viewModel: viewModel
            )
        case .trigger(let taskID):
            USBCopyTaskDetailsSheet(
                taskID: taskID,
                destination: .trigger,
                viewModel: viewModel
            )
        case .filter(let taskID):
            USBCopyTaskDetailsSheet(
                taskID: taskID,
                destination: .filter,
                viewModel: viewModel
            )
        case .logs:
            USBCopyLogSheet { filter, offset, limit in
                try await viewModel.logs(filter: filter, offset: offset, limit: limit)
            }
        case .globalSettings:
            USBCopyGlobalSettingsSheet(
                load: viewModel.globalSettings,
                loadVolumePaths: viewModel.repositoryVolumePaths,
                onSave: viewModel.saveGlobalSettings
            )
        }
    }

    @ViewBuilder
    private func contextMenu(for task: USBCopyTask) -> some View {
        if task.canCancel {
            Button("usb_copy.list.cancel_copy.button") { Task { await announce(viewModel.cancel(task)) } }
        } else if task.canRun {
            Button("usb_copy.list.run.button") { requestRun(task) }
        }
        if !task.isActive {
            Divider()
            Button("usb_copy.list.task_settings.menu") { presentedSheet = .edit(task.id) }
            Button("usb_copy.list.trigger.menu") { presentedSheet = .trigger(task.id) }
            Button("usb_copy.list.file_filter.menu") { presentedSheet = .filter(task.id) }
        }
        if task.canToggleEnabled || task.canDelete {
            Divider()
        }
        if task.canEnable {
            Button("common.button.enable") { requestEnable(task) }
        } else if task.canDisable {
            Button("common.button.disable") { Task { await announce(viewModel.disable(task)) } }
        }
        if task.canDelete {
            Button("common.menu.delete", role: .destructive) { pendingDeletion = task }
        }
    }

    /// DSM sends 0 for a task that has never run, which formatted as a date would read as
    /// January 1970 rather than as an absence.
    private func lastRunText(_ task: USBCopyTask) -> String {
        guard let finishTime = task.latestFinishTime, finishTime > 0 else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(finishTime))
            .formatted(date: .abbreviated, time: .shortened)
    }

    private func selectedTaskStatus(_ task: USBCopyTask) -> String {
        task.knownStatus?.localizedName ?? String(localized: "usb_copy.task.status.unknown", defaultValue: "Unknown status: \(task.status)")
    }

    private func requestEnable(_ task: USBCopyTask) {
        if task.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            presentedSheet = .edit(task.id)
        } else {
            Task { await announce(viewModel.enable(task)) }
        }
    }

    private func requestRun(_ task: USBCopyTask) {
        if task.knownStrategy == .mirror || task.removeSourceFile == true {
            pendingHighImpactRun = task
        } else {
            Task { await announce(viewModel.run(task)) }
        }
    }

    private func announce(_ outcome: DSMOperationOutcome) async {
        VoiceOver.announce(outcome, priority: .high)
    }
}


private enum USBCopyPresentedSheet: Identifiable {
    case create
    case edit(Int)
    case trigger(Int)
    case filter(Int)
    case logs
    case globalSettings

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let taskID): "edit-\(taskID)"
        case .trigger(let taskID): "trigger-\(taskID)"
        case .filter(let taskID): "filter-\(taskID)"
        case .logs: "logs"
        case .globalSettings: "global-settings"
        }
    }
}

enum USBCopyTaskSheetDestination {
    case edit
    case trigger
    case filter
}

private struct USBCopyTaskDetailsSheet: View {
    let taskID: Int
    let destination: USBCopyTaskSheetDestination
    @Bindable var viewModel: USBCopyViewModel

    @State private var details: USBCopyTaskDetails?
    @State private var errorMessage: String?
    @AccessibilityFocusState private var contentFocused: Bool

    var body: some View {
        Group {
            if let details {
                switch destination {
                case .edit:
                    USBCopyTaskEditorSheet(
                        details: details,
                        localShares: viewModel.localShares,
                        externalShares: viewModel.externalShares,
                        loadFolders: viewModel.folders,
                        onSave: viewModel.save
                    )
                case .trigger:
                    USBCopyTriggerEditorSheet(
                        task: details.task,
                        trigger: details.trigger
                    ) { trigger in
                        await viewModel.save(trigger, task: details.task)
                    }
                case .filter:
                    USBCopyFilterEditorSheet(
                        task: details.task,
                        filter: details.filter
                    ) { filter in
                        await viewModel.save(filter, task: details.task)
                    }
                }
            } else if let errorMessage {
                ModuleErrorView(message: errorMessage) { Task { await loadDetails() } }
                    .frame(minWidth: 520, minHeight: 360)
                    .accessibilityFocused($contentFocused)
            } else {
                ModuleLoadingView("usb_copy.list.loading_task")
                    .frame(minWidth: 520, minHeight: 360)
                    .accessibilityFocused($contentFocused)
            }
        }
        .task { await loadDetails() }
    }

    private func loadDetails() async {
        details = nil
        errorMessage = nil
        VoiceOver.announce(String(localized: "usb_copy.list.loading_task"), category: .progress)
        do {
            details = try await viewModel.details(taskID: taskID)
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
        guard !Task.isCancelled else { return }
        contentFocused = true
    }
}
