//
//  DownloadStationView.swift
//  dsmaccess
//
//  Native management of Download Station tasks, as a sortable table: every value keeps its
//  own column, so a rate or a progress can be read on its own instead of being buried in a
//  row read as a single sentence.
//

import SwiftUI

struct DownloadStationView: View {
    @State private var viewModel: DownloadStationViewModel
    @State private var selection: Set<String> = []
    @State private var order = [KeyPathComparator(\DownloadTask.title, order: .forward)]
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
                    Task { await present(viewModel.create(uri: uri, destination: destination)) }
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
            Table(
                filteredTasks.sorted(using: order),
                selection: $selection,
                sortOrder: $order
            ) {
                TableColumn("common.column.name", value: \.title) { task in
                    Text(task.title)
                }
                TableColumn("common.column.state", value: \.sortableStatus) { task in
                    Text(task.statusDescription)
                }
                TableColumn("common.column.progress", value: \.sortableProgress) { task in
                    Text(progressText(task))
                }
                TableColumn("common.column.size", value: \.size) { task in
                    Text(sizeSummary(task))
                }
                TableColumn("download_station.column.download_rate", value: \.downloadSpeed) { task in
                    Text(rateText(task.downloadSpeed))
                }
                TableColumn("download_station.column.upload_rate", value: \.uploadSpeed) { task in
                    Text(rateText(task.uploadSpeed))
                }
                TableColumn("common.column.destination", value: \.sortableDestination) { task in
                    Text(task.destination ?? "—")
                }
            }
            .accessibilityLabel("download_station.title")
            .accessibilityFocused($contentFocused)
            .contextMenu(forSelectionType: String.self) { ids in
                taskActions(for: ids)
            }
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

    @ViewBuilder
    private func taskActions(for ids: Set<String>) -> some View {
        let targets = viewModel.tasks.filter { ids.contains($0.id) }
        if targets.contains(where: \.canPause) {
            Button("download_station.action.pause") {
                Task { await pause(ids: Set(targets.filter(\.canPause).map(\.id))) }
            }
        }
        if targets.contains(where: \.canResume) {
            Button("download.button.resume") {
                Task { await resume(ids: Set(targets.filter(\.canResume).map(\.id))) }
            }
        }
        Divider()
        Button("common.menu.delete", role: .destructive) {
            selection = ids
            showDeleteConfirmation = true
        }
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
        .foregroundStyle(.readableSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var filteredTasks: [DownloadTask] {
        guard !searchText.isEmpty else { return viewModel.tasks }
        return viewModel.tasks.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.statusDescription.localizedStandardContains(searchText)
                || ($0.destination?.localizedStandardContains(searchText) == true)
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
        await present(viewModel.pause(ids: ids))
    }

    private func resume(ids: Set<String>) async {
        await present(viewModel.resume(ids: ids))
    }

    private func deleteSelection(forceComplete: Bool) async {
        let ids = selection
        selection.removeAll()
        await present(viewModel.delete(ids: ids, forceComplete: forceComplete))
    }

    private func present(_ outcome: DSMOperationOutcome) async {
        OperationFailures.shared.present(outcome, from: .downloads)
    }

    private func sizeSummary(_ task: DownloadTask) -> String {
        let downloaded = task.downloaded.formatted(.byteCount(style: .file))
        guard task.size > 0 else { return downloaded }
        return String(localized: "common.format.value_of_total", defaultValue: "\(downloaded) of \(task.size.formatted(.byteCount(style: .file)))")
    }

    private func speed(_ bytesPerSecond: Int64) -> String {
        String(localized: "download_station.rate.per_second", defaultValue: "\(bytesPerSecond.formatted(.byteCount(style: .file))) per second")
    }

    /// A dash rather than "0 bytes per second": a task that is not transferring has no rate,
    /// and the columns of the other modules mark an absent value the same way.
    private func rateText(_ bytesPerSecond: Int64) -> String {
        bytesPerSecond > 0 ? speed(bytesPerSecond) : "—"
    }

    private func progressText(_ task: DownloadTask) -> String {
        guard let progress = task.progress else { return "—" }
        return progress.formatted(.percent.precision(.fractionLength(0)))
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
                .foregroundStyle(.readableSecondary)
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
