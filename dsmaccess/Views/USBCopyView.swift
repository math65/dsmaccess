//
//  USBCopyView.swift
//  dsmaccess
//
//  Gestion native et accessible des tâches USB Copy.
//

import SwiftUI

struct USBCopyView: View {
    @State private var viewModel: USBCopyViewModel
    @State private var selection: Int?
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
            .searchable(text: $searchText, prompt: "Rechercher une tâche USB Copy")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .task(id: activeTaskIDs) { await refreshActiveTasks() }
            .sheet(item: $presentedSheet) { sheet in
                sheetContent(sheet)
            }
            .confirmationDialog(
                "Supprimer la tâche USB Copy ?",
                isPresented: deletionPresented
            ) {
                Button("Supprimer la tâche", role: .destructive) {
                    if let task = pendingDeletion {
                        Task { await announce(viewModel.delete(task)) }
                    }
                    pendingDeletion = nil
                }
                Button("Annuler", role: .cancel) { pendingDeletion = nil }
            } message: {
                if let task = pendingDeletion {
                    Text("La tâche « \(task.name) » sera définitivement supprimée de USB Copy. Cette action est irréversible. Vérifiez que vous n’avez plus besoin de sa configuration ni de son historique.")
                }
            }
            .confirmationDialog(
                "Exécuter cette tâche USB Copy ?",
                isPresented: highImpactRunPresented
            ) {
                Button("Exécuter la tâche", role: .destructive) {
                    if let task = pendingHighImpactRun {
                        Task { await announce(viewModel.run(task)) }
                    }
                    pendingHighImpactRun = nil
                }
                Button("Annuler", role: .cancel) { pendingHighImpactRun = nil }
            } message: {
                if let task = pendingHighImpactRun {
                    if task.knownStrategy == .mirror {
                        Text("La tâche « \(task.name) » supprimera de la destination les fichiers qui ne sont plus présents à la source.")
                    } else {
                        Text("La tâche « \(task.name) » supprimera les fichiers source après leur copie vers la destination.")
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
            ModuleLoadingView("Chargement des tâches USB Copy…")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage, viewModel.tasks.isEmpty {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredTasks.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "Aucune tâche USB Copy" : "Aucun résultat",
                systemImage: "externaldrive.badge.arrowtriangle.2.circlepath",
                description: searchText.isEmpty
                    ? "Créez une tâche pour importer ou exporter des fichiers avec un périphérique USB."
                    : "Modifiez votre recherche et réessayez."
            )
            .accessibilityFocused($contentFocused)
        } else {
            List(filteredTasks, selection: $selection) { task in
                USBCopyTaskRow(task: task)
                    .tag(task.id)
                    .contextMenu { contextMenu(for: task) }
                    .accessibilityActions { accessibilityActions(for: task) }
            }
            .accessibilityLabel("Tâches USB Copy")
            .accessibilityFocused($contentFocused)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button("Créer une tâche", systemImage: "plus") {
                presentedSheet = .create
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("Créer une tâche USB Copy")
        }

        ToolbarItem {
            if selectedTask?.canCancel == true {
                Button("Annuler la copie", systemImage: "stop.fill") {
                    if let task = selectedTask { Task { await announce(viewModel.cancel(task)) } }
                }
                .disabled(selectedTaskIsBusy)
                .help("Arrêter la tâche USB Copy sélectionnée")
            } else {
                Button("Exécuter", systemImage: "play.fill") {
                    if let task = selectedTask { requestRun(task) }
                }
                .disabled(selectedTask?.canRun != true || selectedTaskIsBusy)
                .help("Exécuter la tâche USB Copy sélectionnée")
            }
        }

        ToolbarItem {
            Menu("Modifier la tâche", systemImage: "slider.horizontal.3") {
                Button("Réglages de la tâche…") { presentSelected(.edit) }
                Button("Déclenchement…") { presentSelected(.trigger) }
                Button("Filtre de fichiers…") { presentSelected(.filter) }
            }
            .disabled(selectedTask == nil || selectedTask?.isActive == true || selectedTaskIsBusy)
            .help(
                selectedTask?.isActive == true
                    ? "Annulez la copie avant de modifier cette tâche"
                    : "Modifier la tâche USB Copy sélectionnée"
            )
        }

        ToolbarItem {
            Menu("État de la tâche", systemImage: "power") {
                if selectedTask?.canEnable == true {
                    Button("Activer") {
                        if let task = selectedTask { requestEnable(task) }
                    }
                } else if selectedTask?.canDisable == true {
                    Button("Désactiver") {
                        if let task = selectedTask { Task { await announce(viewModel.disable(task)) } }
                    }
                }
            }
            .disabled(selectedTask?.canToggleEnabled != true || selectedTaskIsBusy)
            .help("Activer ou désactiver la tâche USB Copy sélectionnée")
        }

        ToolbarItem {
            Button(role: .destructive) {
                pendingDeletion = selectedTask
            } label: {
                Label("Supprimer la tâche", systemImage: "trash")
            }
            .disabled(selectedTask?.canDelete != true || selectedTaskIsBusy)
            .help("Supprimer la tâche USB Copy sélectionnée")
        }

        ToolbarItem {
            Menu("Plus d’options", systemImage: "ellipsis.circle") {
                Button("Journal USB Copy…", systemImage: "list.bullet.rectangle") {
                    presentedSheet = .logs
                }
                Button("Réglages généraux…", systemImage: "gearshape") {
                    presentedSheet = .globalSettings
                }
            }
            .help("Ouvrir le journal ou les réglages généraux de USB Copy")
        }

        ToolbarItem {
            Button("Actualiser", systemImage: "arrow.clockwise") {
                Task { await load() }
            }
            .help("Actualiser les tâches USB Copy")
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
        .foregroundStyle(.secondary)
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
            String(localized: "Chargement des tâches USB Copy…"),
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
            Button("Annuler la copie") { Task { await announce(viewModel.cancel(task)) } }
        } else if task.canRun {
            Button("Exécuter") { requestRun(task) }
        }
        if !task.isActive {
            Divider()
            Button("Réglages de la tâche…") { presentedSheet = .edit(task.id) }
            Button("Déclenchement…") { presentedSheet = .trigger(task.id) }
            Button("Filtre de fichiers…") { presentedSheet = .filter(task.id) }
        }
        if task.canToggleEnabled || task.canDelete {
            Divider()
        }
        if task.canEnable {
            Button("Activer") { requestEnable(task) }
        } else if task.canDisable {
            Button("Désactiver") { Task { await announce(viewModel.disable(task)) } }
        }
        if task.canDelete {
            Button("Supprimer…", role: .destructive) { pendingDeletion = task }
        }
    }

    @ViewBuilder
    private func accessibilityActions(for task: USBCopyTask) -> some View {
        if task.canCancel {
            Button("Annuler la copie") { Task { await announce(viewModel.cancel(task)) } }
        } else if task.canRun {
            Button("Exécuter") { requestRun(task) }
        }
        if !task.isActive {
            Button("Modifier les réglages") { presentedSheet = .edit(task.id) }
            Button("Modifier le déclenchement") { presentedSheet = .trigger(task.id) }
            Button("Modifier le filtre") { presentedSheet = .filter(task.id) }
        }
    }

    private func selectedTaskStatus(_ task: USBCopyTask) -> String {
        task.knownStatus?.localizedName ?? String(localized: "État inconnu : \(task.status)")
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

private struct USBCopyTaskRow: View {
    let task: USBCopyTask

    var body: some View {
        HStack {
            Image(systemName: statusImage)
                .foregroundStyle(statusStyle)
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(task.name).bold()
                Text(task.knownType?.localizedName ?? task.type)
                    .foregroundStyle(.secondary)
                Text("\(task.sourcePath) → \(task.destinationPath)")
                HStack {
                    Text(task.knownStatus?.localizedName ?? task.status)
                    Text(task.knownStrategy?.localizedName ?? task.copyStrategy)
                    if let latestFinishTime = task.latestFinishTime, latestFinishTime > 0 {
                        Text(Date(timeIntervalSince1970: TimeInterval(latestFinishTime)), format: .dateTime)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            task.name,
            task.knownType?.localizedName ?? task.type,
            String(localized: "de \(task.sourcePath) vers \(task.destinationPath)"),
            task.knownStatus?.localizedName ?? task.status,
            task.knownStrategy?.localizedName ?? task.copyStrategy,
        ].formatted(.list(type: .and))
    }

    private var statusImage: String {
        switch task.knownStatus {
        case .successful: "checkmark.circle.fill"
        case .failed, .shareDeleted, .shareUnavailable: "exclamationmark.triangle.fill"
        case .copying: "arrow.right.circle.fill"
        case .waiting: "clock.fill"
        case .disabled: "pause.circle.fill"
        case .unmounted: "externaldrive.badge.xmark"
        case .canceling: "stop.circle.fill"
        case .notAvailable: "questionmark.circle"
        case .initial, .none: "circle"
        }
    }

    private var statusStyle: Color {
        switch task.knownStatus {
        case .successful: .green
        case .failed, .shareDeleted, .shareUnavailable: .red
        case .disabled, .unmounted, .notAvailable: .secondary
        default: .accentColor
        }
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
                ModuleLoadingView("Chargement de la tâche USB Copy…")
                    .frame(minWidth: 520, minHeight: 360)
                    .accessibilityFocused($contentFocused)
            }
        }
        .task { await loadDetails() }
    }

    private func loadDetails() async {
        details = nil
        errorMessage = nil
        VoiceOver.announce(String(localized: "Chargement de la tâche USB Copy…"), category: .progress)
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
