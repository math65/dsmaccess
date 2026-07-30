//
//  DownloadStationView.swift
//  dsmaccess
//
//  Native management of Download Station tasks.
//

import SwiftUI

struct DownloadStationView: View {
    @State private var viewModel: DownloadStationViewModel
    @State private var selection: Set<String> = []
    @State private var searchText = ""
    @State private var showCreateSheet = false
    @State private var showDeleteConfirmation = false
    @State private var autoRefresh = true
    @AccessibilityFocusState private var contentFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: DownloadStationViewModel(session: session))
    }

    var body: some View {
        content
            .searchable(text: $searchText, prompt: "download.search.placeholder")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .task(id: autoRefresh) { await refreshPeriodically() }
            .sheet(isPresented: $showCreateSheet) {
                CreateDownloadSheet { uri, destination in
                    Task { await announce(viewModel.create(uri: uri, destination: destination)) }
                }
            }
            .confirmationDialog(
                "download.delete.confirm.title",
                isPresented: $showDeleteConfirmation
            ) {
                Button("common.button.delete", role: .destructive) {
                    Task { await deleteSelection(forceComplete: false) }
                }
                .help("download.button.remove_selected")
                Button("download_station.remove.mark_completed.button", role: .destructive) {
                    Task { await deleteSelection(forceComplete: true) }
                }
                .help("download.delete.confirm.hint")
                Button("common.button.cancel", role: .cancel) { }
                    .help("download_station.remove.keep.button")
            } message: {
                Text("download.delete.confirm.message")
            }
            .onChange(of: viewModel.tasks) {
                selection.formIntersection(Set(viewModel.tasks.map(\.id)))
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.tasks.isEmpty {
            ModuleLoadingView("download_station.loading")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredTasks.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "download_station.empty.title" : "common.empty.results",
                systemImage: "arrow.down.circle",
                description: searchText.isEmpty
                    ? "download_station.empty.description"
                    : "common.empty.results.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            List(filteredTasks, selection: $selection) { task in
                taskRow(task)
                    .tag(task.id)
                    .contextMenu { taskActions(task) }
            }
            .accessibilityLabel("download_station.title")
            .accessibilityFocused($contentFocused)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                showCreateSheet = true
            } label: {
                Label("download_station.add.title", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("download_station.add.title")
        }

        ToolbarItem {
            Button {
                Task { await pauseSelection() }
            } label: {
                Label("download_station.action.pause", systemImage: "pause")
            }
            .disabled(!selectionCanPause || selectionIsBusy)
            .help("download_station.action.pause.hint")
        }

        ToolbarItem {
            Button {
                Task { await resumeSelection() }
            } label: {
                Label("download.button.resume", systemImage: "play")
            }
            .disabled(!selectionCanResume || selectionIsBusy)
            .help("download.button.resume.hint")
        }

        ToolbarItem {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("common.button.delete", systemImage: "trash")
            }
            .disabled(selection.isEmpty || selectionIsBusy)
            .help("download_station.action.remove.hint")
        }

        ToolbarItem {
            Menu {
                Toggle("common.label.automatic_refresh", isOn: $autoRefresh)
                    .help("download_station.toolbar.auto_refresh")
            } label: {
                Label("common.label.refresh_options", systemImage: "ellipsis.circle")
            }
            .help("common.label.refresh_options")
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("common.button.refresh", systemImage: "arrow.clockwise")
            }
            .help("download_station.toolbar.refresh")
        }
    }

    private func taskRow(_ task: DownloadTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: task.status))
                .foregroundStyle(color(for: task.status))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(task.title).fontWeight(.medium)
                    Spacer()
                    Text(statusText(task.status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let progress = task.progress {
                    ProgressView(value: progress)
                        .accessibilityLabel(String(localized: "common.label.progress_for", defaultValue: "\(task.title) progress"))
                        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
                }
                HStack {
                    Text(sizeSummary(task))
                    Spacer()
                    if task.downloadSpeed > 0 {
                        Label(speed(task.downloadSpeed), systemImage: "arrow.down")
                    }
                    if task.uploadSpeed > 0 {
                        Label(speed(task.uploadSpeed), systemImage: "arrow.up")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(taskAccessibilityLabel(task))
        .accessibilityActions {
            if task.canPause {
                Button("download_station.action.pause") { Task { await pause(ids: [task.id]) } }
                    .help("download_station.action.pause_one.hint")
            }
            if task.canResume {
                Button("download.button.resume") { Task { await resume(ids: [task.id]) } }
                    .help("download.row.resume.hint")
            }
            Button("common.menu.delete", role: .destructive) {
                selection = [task.id]
                showDeleteConfirmation = true
            }
            .help("download_station.action.delete_one.hint")
        }
    }

    @ViewBuilder
    private func taskActions(_ task: DownloadTask) -> some View {
        if task.canPause {
            Button("download_station.action.pause") { Task { await pause(ids: [task.id]) } }
                .help("download_station.action.pause_one.hint")
        }
        if task.canResume {
            Button("download.button.resume") { Task { await resume(ids: [task.id]) } }
                .help("download.row.resume.hint")
        }
        Divider()
        Button("common.menu.delete", role: .destructive) {
            selection = [task.id]
            showDeleteConfirmation = true
        }
        .help("download_station.action.delete_one.hint")
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text(viewModel.summary)
            Spacer()
            if let statistic = viewModel.statistic {
                Label(speed(statistic.downloadSpeed), systemImage: "arrow.down")
                    .accessibilityLabel(String(localized: "download_station.summary.download_rate", defaultValue: "Download rate: \(speed(statistic.downloadSpeed))"))
                Label(speed(statistic.uploadSpeed), systemImage: "arrow.up")
                    .accessibilityLabel(String(localized: "download.detail.upload_rate", defaultValue: "Upload rate: \(speed(statistic.uploadSpeed))"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var filteredTasks: [DownloadTask] {
        guard !searchText.isEmpty else { return viewModel.tasks }
        return viewModel.tasks.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.status.localizedStandardContains(searchText)
                || ($0.additional?.detail?.destination?.localizedStandardContains(searchText) == true)
        }
    }

    private var selectedTasks: [DownloadTask] {
        viewModel.tasks.filter { selection.contains($0.id) }
    }

    private var selectionCanPause: Bool { selectedTasks.contains(where: \.canPause) }
    private var selectionCanResume: Bool { selectedTasks.contains(where: \.canResume) }
    private var selectionIsBusy: Bool { !viewModel.busyIDs.isDisjoint(with: selection) }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "download_station.loading"),
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

    private func pauseSelection() async {
        await pause(ids: Set(selectedTasks.filter(\.canPause).map(\.id)))
    }

    private func resumeSelection() async {
        await resume(ids: Set(selectedTasks.filter(\.canResume).map(\.id)))
    }

    private func pause(ids: Set<String>) async {
        await announce(viewModel.pause(ids: ids))
    }

    private func resume(ids: Set<String>) async {
        await announce(viewModel.resume(ids: ids))
    }

    private func deleteSelection(forceComplete: Bool) async {
        let ids = selection
        selection.removeAll()
        await announce(viewModel.delete(ids: ids, forceComplete: forceComplete))
    }

    private func announce(_ outcome: DSMOperationOutcome) async {
        VoiceOver.announce(outcome, priority: .high)
    }

    private func sizeSummary(_ task: DownloadTask) -> String {
        let downloaded = task.downloaded.formatted(.byteCount(style: .file))
        guard task.size > 0 else { return downloaded }
        return String(localized: "common.format.value_of_total", defaultValue: "\(downloaded) of \(task.size.formatted(.byteCount(style: .file)))")
    }

    private func speed(_ bytesPerSecond: Int64) -> String {
        String(localized: "download_station.rate.per_second", defaultValue: "\(bytesPerSecond.formatted(.byteCount(style: .file))) per second")
    }

    private func taskAccessibilityLabel(_ task: DownloadTask) -> String {
        var parts = [task.title, statusText(task.status), sizeSummary(task)]
        if task.downloadSpeed > 0 { parts.append(String(localized: "download.row.download_rate", defaultValue: "download \(speed(task.downloadSpeed))")) }
        if task.uploadSpeed > 0 { parts.append(String(localized: "download.row.upload_rate", defaultValue: "upload \(speed(task.uploadSpeed))")) }
        return parts.formatted(.list(type: .and))
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "waiting": String(localized: "common.status.waiting")
        case "downloading": String(localized: "download_station.column.name")
        case "paused": String(localized: "download_station.status.paused")
        case "finishing": String(localized: "download_station.status.finishing")
        case "finished": String(localized: "common.status.done")
        case "hash_checking": String(localized: "download_station.status.checking")
        case "seeding": String(localized: "download.section.sharing")
        case "filehosting_waiting": String(localized: "download.status.waiting_host")
        case "extracting": String(localized: "common.operation.extraction")
        case "error": String(localized: "common.level.error")
        default: String(localized: "common.status.unknown")
        }
    }

    private func icon(for status: String) -> String {
        switch status {
        case "downloading", "finishing": "arrow.down.circle.fill"
        case "seeding": "arrow.up.circle.fill"
        case "finished": "checkmark.circle.fill"
        case "paused": "pause.circle.fill"
        case "error": "exclamationmark.triangle.fill"
        default: "clock"
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "finished": .green
        case "error": .red
        case "paused": .secondary
        default: .accentColor
        }
    }
}

private struct CreateDownloadSheet: View {
    let onCreate: (_ uri: String, _ destination: String?) -> Void

    @State private var uri = ""
    @State private var destination = ""
    @FocusState private var uriFocused: Bool
    @AccessibilityFocusState private var accessibilityFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmedURI: String { uri.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("download_station.add.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LabeledField(label: "download_station.add.url.label") {
                TextField("download.add.url.placeholder", text: $uri)
                    .focused($uriFocused)
                    .accessibilityFocused($accessibilityFocused)
                    .onSubmit(create)
                    .help("download_station.add.url.hint")
            }
            LabeledField(label: "download_station.add.destination.label") {
                TextField("download.destination.placeholder", text: $destination)
                    .help("download_station.add.destination.hint")
            }
            Text("download_station.add.destination.footer")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("download_station.add.cancel.hint")
                Button("common.button.add", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedURI.isEmpty)
                    .help("download_station.add.confirm.hint")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            uriFocused = true
            accessibilityFocused = true
            VoiceOver.announce(
                String(localized: "download_station.add.title"),
                category: .navigation
            )
        }
    }

    private func create() {
        guard !trimmedURI.isEmpty else { return }
        let destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(trimmedURI, destination.isEmpty ? nil : destination)
        dismiss()
    }
}
