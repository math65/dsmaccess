//
//  FileStationTasksView.swift
//  dsmaccess
//
//  Suivi des opérations asynchrones conservées par File Station sur le NAS.
//

import SwiftUI

struct FileStationTasksView: View {
    @Bindable var vm: FileBrowserViewModel

    @State private var operationError: String?
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusStatus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tâches File Station")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            if let operationError {
                Text(operationError)
                    .foregroundStyle(.red)
                    .accessibilityFocused($focusStatus)
            }

            content

            HStack {
                Button("Effacer les tâches terminées") {
                    Task { await clearFinishedTasks() }
                }
                .disabled(
                    vm.isLoadingBackgroundTasks
                        || !vm.backgroundTasks.contains(where: \.finished)
                )
                .help("Retirer de l’historique les opérations terminées")

                Button("Actualiser") { Task { await loadTasks() } }
                    .disabled(vm.isLoadingBackgroundTasks)
                    .help("Actualiser les tâches File Station")

                Spacer()

                Button("Fermer", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .task {
            focusHeading = true
            await loadTasks()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingBackgroundTasks && vm.backgroundTasks.isEmpty {
            ModuleLoadingView("Chargement des tâches File Station…")
                .accessibilityFocused($focusStatus)
        } else if let error = vm.backgroundTasksError {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Réessayer") { Task { await loadTasks() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if vm.backgroundTasks.isEmpty {
            ContentUnavailableView(
                "Aucune tâche File Station",
                systemImage: "list.bullet.rectangle",
                description: Text("Les opérations de copie, compression, extraction et suppression apparaîtront ici.")
            )
            .accessibilityFocused($focusStatus)
        } else {
            List(vm.backgroundTasks) { task in
                taskRow(task)
            }
            .accessibilityLabel("Historique des tâches File Station")
        }
    }

    private func taskRow(_ task: FileStationBackgroundTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.operationLabel)
                    .font(.headline)
                Spacer()
                Text(task.finished ? "Terminée" : "En cours")
                    .foregroundStyle(.secondary)
            }

            if let path = task.processingPath ?? task.path {
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let fraction = task.normalizedProgress {
                ProgressView(value: fraction)
                    .accessibilityLabel(String(localized: "Progression de \(task.operationLabel)"))
                    .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
            }

            HStack {
                if let creationTime = task.creationTime {
                    Text(
                        Date(timeIntervalSince1970: TimeInterval(creationTime)),
                        format: Date.FormatStyle(date: .abbreviated, time: .shortened)
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if !task.finished, FileOperationKind(rawValue: task.api) != nil {
                    Button("Arrêter", role: .destructive) {
                        Task { await stop(task) }
                    }
                    .help(String(localized: "Arrêter la tâche \(task.operationLabel)"))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private func loadTasks() async {
        operationError = nil
        await vm.loadBackgroundTasks()
        guard !Task.isCancelled else { return }
        if vm.backgroundTasksError == nil {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "\(vm.backgroundTasks.count) tâches File Station"),
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

private extension FileStationBackgroundTask {
    var normalizedProgress: Double? {
        if finished { return 1 }
        return progress.map { min(max($0, 0), 1) }
    }

    var operationLabel: String {
        FileOperationKind(rawValue: api)?.label ?? api
    }
}
