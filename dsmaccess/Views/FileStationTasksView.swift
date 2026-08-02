//
//  FileStationTasksView.swift
//  dsmaccess
//
//  Tracking the asynchronous operations File Station keeps on the NAS.
//

import SwiftUI

struct FileStationTasksView: View {
    @Bindable var vm: FileBrowserViewModel

    @State private var operationError: String?
    @State private var automaticFollowStopped = false
    @State private var selection = Set<FileStationBackgroundTask.ID>()
    @State private var order = [
        KeyPathComparator(\FileStationBackgroundTask.sortableCreationDate, order: .reverse)
    ]
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("common.action.file_station_tasks")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            if let operationError {
                Text(operationError)
                    .foregroundStyle(.readableRed)
                    .accessibilityFocused($focusStatus)
            }

            if automaticFollowStopped {
                Text("file_tasks.polling_stopped.description")
                    .font(.callout)
                    .foregroundStyle(.readableOrange)
            }

            content

            HStack {
                Button("file_tasks.clear_finished.button") {
                    Task { await clearFinishedTasks() }
                }
                .disabled(
                    vm.isLoadingBackgroundTasks
                        || !vm.backgroundTasks.contains(where: \.finished)
                )
                .help("file_tasks.clear_finished.hint")

                Button("common.button.refresh") { Task { await loadTasks() } }
                    .disabled(vm.isLoadingBackgroundTasks)
                    .help("file_tasks.refresh.label")

                Spacer()

                Button("common.button.close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .task {
            focusHeading = true
            await loadTasks()
            await followRunningTasks()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingBackgroundTasks && vm.backgroundTasks.isEmpty {
            ModuleLoadingView("file_tasks.loading")
                .accessibilityFocused($focusStatus)
        } else if let error = vm.backgroundTasksError {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.readableRed)
                    .multilineTextAlignment(.center)
                Button("common.button.retry") { Task { await loadTasks() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if vm.backgroundTasks.isEmpty {
            ContentUnavailableView(
                "file_tasks.empty",
                systemImage: "list.bullet.rectangle",
                description: Text("file_tasks.empty.description")
            )
            .accessibilityFocused($focusStatus)
        } else {
            Table(
                vm.backgroundTasks.sorted(using: order),
                selection: $selection,
                sortOrder: $order
            ) {
                TableColumn("common.column.operation", value: \.sortableOperation) { task in
                    Text(task.operationLabel)
                }
                TableColumn("common.column.location", value: \.sortableLocation) { task in
                    Text(task.location ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("common.column.state", value: \.sortableStatus) { task in
                    Text(task.statusDescription)
                        .foregroundStyle(.readableSecondary)
                }
                TableColumn("common.column.progress", value: \.sortableProgress) { task in
                    Text(task.progressDescription)
                }
                TableColumn("common.column.creation_date", value: \.sortableCreationDate) { task in
                    if let date = task.creationDate {
                        Text(date, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    } else {
                        Text("—")
                    }
                }
            }
            .accessibilityLabel("file_tasks.table.label")
            .contextMenu(forSelectionType: FileStationBackgroundTask.ID.self) { ids in
                if let task = vm.backgroundTasks.first(where: { ids.contains($0.id) && $0.canStop }) {
                    Button("common.button.stop", role: .destructive) {
                        Task { await stop(task) }
                    }
                }
            }
        }
    }

    /// The NAS reports nothing on its own: without re-reading, the window keeps progress
    /// frozen at the moment it opened. The re-read stays silent and does not move the
    /// VoiceOver cursor, which would otherwise be dragged back to the top of the window
    /// every three seconds.
    private func followRunningTasks() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !automaticFollowStopped,
                  vm.backgroundTasksError == nil,
                  vm.backgroundTasks.contains(where: { !$0.finished })
            else { continue }
            guard await vm.refreshBackgroundTasksQuietly() else {
                // A single announcement: tracking will only resume after "Refresh", so the
                // message will not repeat from one round to the next. The loop must keep
                // spinning idle: it is what starts up again when "Refresh" clears the flag.
                // Leaving it here would make the button misleading, with the warning
                // disappearing without tracking resuming.
                automaticFollowStopped = true
                VoiceOver.announce(
                    String(localized: "file_tasks.polling_stopped.title"),
                    category: .error,
                    priority: .high
                )
                continue
            }
            if !vm.backgroundTasks.contains(where: { !$0.finished }) {
                VoiceOver.announce(
                    String(localized: "file_tasks.all_finished.announcement"),
                    category: .result
                )
            }
        }
    }

    private func loadTasks() async {
        operationError = nil
        automaticFollowStopped = false
        await vm.loadBackgroundTasks()
        guard !Task.isCancelled else { return }
        if vm.backgroundTasksError == nil {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "file_tasks.count", defaultValue: "\(vm.backgroundTasks.count) File Station tasks"),
                category: .result
            )
        } else if let error = vm.backgroundTasksError {
            focusStatus = true
            VoiceOver.announce(
                error,
                category: .error,
                priority: .high
            )
        }
    }

    private func stop(_ task: FileStationBackgroundTask) async {
        operationError = nil
        let outcome = await vm.stopBackgroundTask(task)
        if case .failure(let message) = outcome {
            operationError = message
            focusStatus = true
        }
        VoiceOver.announce(outcome, priority: .high)
    }

    private func clearFinishedTasks() async {
        operationError = nil
        let outcome = await vm.clearFinishedBackgroundTasks()
        if case .failure(let message) = outcome {
            operationError = message
            focusStatus = true
        }
        VoiceOver.announce(outcome, priority: .high)
    }
}
