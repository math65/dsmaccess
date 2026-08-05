//
//  HyperBackupView.swift
//  dsmaccess
//
//  Native, accessible monitoring of Hyper Backup tasks.
//

import SwiftUI

struct HyperBackupView: View {
    @State private var viewModel: HyperBackupViewModel
    @State private var selection: Int?
    @State private var order = [KeyPathComparator(\HyperBackupTask.name, order: .forward)]
    @State private var searchText = ""
    @State private var presentedSheet: HyperBackupPresentedSheet?
    @State private var pendingCancellation: HyperBackupTask?
    @State private var runningTaskNames: [Int: String] = [:]
    @AccessibilityFocusState private var contentFocused: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _viewModel = State(initialValue: HyperBackupViewModel(session: session))
    }

    var body: some View {
        content
            .searchable(text: $searchText, prompt: "hyper_backup.list.search.label")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .task(id: runningTaskIDs) { await followRunningTasks() }
            .sheet(item: $presentedSheet) { sheet in
                sheetContent(sheet)
            }
            .confirmationDialog(
                "hyper_backup.list.cancel.confirm.title",
                isPresented: cancellationPresented
            ) {
                Button("hyper_backup.list.cancel.button", role: .destructive) {
                    if let task = pendingCancellation {
                        Task { await announce(viewModel.cancel(task)) }
                    }
                    pendingCancellation = nil
                }
                Button("common.button.cancel", role: .cancel) { pendingCancellation = nil }
            } message: {
                if let task = pendingCancellation {
                    Text(String(localized: "hyper_backup.list.cancel.confirm.description", defaultValue: "The backup in progress for “\(task.name)” will be stopped. The partial version is kept but marked as cancelled, and the data already transferred is not removed."))
                }
            }
            .onChange(of: viewModel.tasks) { previous, current in
                announceFinishedBackups(previous: previous, current: current)
                if let selection, !current.contains(where: { $0.taskID == selection }) {
                    self.selection = nil
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            ModuleLoadingView("hyper_backup.list.loading")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage, viewModel.tasks.isEmpty {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredTasks.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "hyper_backup.list.empty.title" : "common.empty.results",
                systemImage: "arrow.triangle.2.circlepath.circle",
                description: searchText.isEmpty
                    ? "hyper_backup.list.empty.description"
                    : "common.empty.results.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            Table(filteredTasks.sorted(using: order), selection: $selection, sortOrder: $order) {
                TableColumn("common.column.name", value: \.name) { task in
                    Text(task.name)
                }
                TableColumn("common.column.destination", value: \.sortableDestination) { task in
                    Text(task.destinationDescription)
                }
                TableColumn("common.column.state", value: \.sortableStatus) { task in
                    Text(task.statusDescription)
                }
                TableColumn("hyper_backup.column.progress") { task in
                    Text(progressCell(task))
                }
                TableColumn("hyper_backup.column.encryption", value: \.sortableEncryption) { task in
                    Text(task.encryptionDescription)
                }
            }
            .accessibilityLabel("hyper_backup.list.title")
            .accessibilityFocused($contentFocused)
            .contextMenu(forSelectionType: Int.self) { ids in
                if let task = viewModel.tasks.first(where: { ids.contains($0.taskID) }) {
                    contextMenu(for: task)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for task: HyperBackupTask) -> some View {
        Button("hyper_backup.list.back_up_now.button") {
            Task { await announce(viewModel.backUp(task)) }
        }
        .disabled(!task.canBackUp || viewModel.busyTaskIDs.contains(task.taskID))

        Button("hyper_backup.list.cancel.button", role: .destructive) {
            pendingCancellation = task
        }
        .disabled(!task.canCancel || viewModel.busyTaskIDs.contains(task.taskID))

        Divider()

        Button("hyper_backup.list.versions.menu") { presentedSheet = .details(task.taskID) }
        Button("hyper_backup.list.log.menu") { presentedSheet = .logs(task.taskID) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            if selectedTask?.canCancel == true {
                Button("hyper_backup.list.cancel.button", systemImage: "stop.fill") {
                    pendingCancellation = selectedTask
                }
                .disabled(selectedTaskIsBusy)
                .help("hyper_backup.list.cancel.hint")
            } else {
                Button("hyper_backup.list.back_up_now.button", systemImage: "play.fill") {
                    if let task = selectedTask { Task { await announce(viewModel.backUp(task)) } }
                }
                .disabled(selectedTask?.canBackUp != true || selectedTaskIsBusy)
                .help("hyper_backup.list.back_up_now.hint")
            }
        }

        ToolbarItem {
            Button("hyper_backup.list.versions.menu", systemImage: "clock.arrow.circlepath") {
                if let task = selectedTask { presentedSheet = .details(task.taskID) }
            }
            .disabled(selectedTask == nil)
            .help("hyper_backup.list.versions.hint")
        }

        ToolbarItem {
            Button("hyper_backup.list.log.menu", systemImage: "list.bullet.rectangle") {
                if let task = selectedTask { presentedSheet = .logs(task.taskID) }
            }
            .disabled(selectedTask == nil)
            .help("hyper_backup.list.log.hint")
        }

        ToolbarItem {
            Button("common.button.refresh", systemImage: "arrow.clockwise") {
                Task { await load() }
            }
            .help("hyper_backup.list.refresh.hint")
        }
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.summary)
            Spacer()
            if let selectedTask {
                Text(viewModel.progressDescription(for: selectedTask))
            }
        }
        .font(.caption)
        .foregroundStyle(.readableSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    /// The cell stays textual: an unstarted task reads as such instead of showing an empty
    /// column, and a running one names its stage rather than relying on a bar.
    private func progressCell(_ task: HyperBackupTask) -> String {
        guard let progress = task.progress else {
            return String(localized: "hyper_backup.progress.idle")
        }
        guard progress.showsPercentage else { return progress.stepDescription }
        return String(localized: "hyper_backup.progress.stage_percentage", defaultValue: "\(progress.stepDescription), \(progress.percentage)%")
    }

    private var filteredTasks: [HyperBackupTask] {
        guard !searchText.isEmpty else { return viewModel.tasks }
        return viewModel.tasks.filter {
            $0.name.localizedStandardContains(searchText)
                || $0.destinationDescription.localizedStandardContains(searchText)
                || $0.statusDescription.localizedStandardContains(searchText)
        }
    }

    private var selectedTask: HyperBackupTask? {
        guard let selection else { return nil }
        return viewModel.tasks.first { $0.taskID == selection }
    }

    private var selectedTaskIsBusy: Bool {
        guard let selection else { return false }
        return viewModel.busyTaskIDs.contains(selection)
    }

    private var runningTaskIDs: Set<Int> {
        Set(viewModel.tasks.filter(\.isRunning).map(\.taskID))
    }

    private var cancellationPresented: Binding<Bool> {
        Binding(
            get: { pendingCancellation != nil },
            set: { if !$0 { pendingCancellation = nil } }
        )
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "hyper_backup.list.loading"),
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

    /// Polls only while something is running, and stays silent: the completion announcement is
    /// made from the state transition instead, so a background refresh never interrupts.
    private func followRunningTasks() async {
        guard !runningTaskIDs.isEmpty else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await viewModel.load(silently: true)
        }
    }

    /// A backup that ends while the user is elsewhere in the module would otherwise pass
    /// unnoticed: the running names are remembered so the outcome can be named when it stops.
    private func announceFinishedBackups(
        previous: [HyperBackupTask],
        current: [HyperBackupTask]
    ) {
        let stillRunning = Dictionary(
            uniqueKeysWithValues: current.filter(\.isRunning).map { ($0.taskID, $0.name) }
        )
        for (taskID, name) in runningTaskNames where stillRunning[taskID] == nil {
            let wasCancelling = previous.first { $0.taskID == taskID }?.knownStatus == .cancelling
            VoiceOver.announce(
                wasCancelling
                    ? String(localized: "hyper_backup.announcement.backup_cancelled", defaultValue: "Backup cancelled: \(name)")
                    : String(localized: "hyper_backup.announcement.backup_finished", defaultValue: "Backup finished: \(name)"),
                category: .result
            )
        }
        runningTaskNames = stillRunning
    }

    @ViewBuilder
    private func sheetContent(_ sheet: HyperBackupPresentedSheet) -> some View {
        switch sheet {
        case .details(let taskID):
            HyperBackupVersionsSheet(
                task: viewModel.tasks.first { $0.taskID == taskID },
                session: session,
                loadDetails: { try await viewModel.details(taskID: taskID) }
            )
        case .logs(let taskID):
            HyperBackupLogSheet(
                task: viewModel.tasks.first { $0.taskID == taskID },
                loadLogs: { try await viewModel.logs(taskID: taskID) }
            )
        }
    }

    private func announce(_ outcome: DSMOperationOutcome) async {
        VoiceOver.announce(outcome, priority: .high)
    }
}

enum HyperBackupPresentedSheet: Identifiable, Hashable {
    case details(Int)
    case logs(Int)

    var id: Self { self }
}
