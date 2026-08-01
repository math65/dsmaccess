//
//  DockerProjectsView.swift
//  dsmaccess
//
//  “Projects” tab of the Containers module. Compose actions stream their docker-compose
//  output: DSM shows it in a terminal window that a screen reader cannot follow, so the app
//  announces the outcome and keeps the full output readable in a report sheet.
//

import SwiftUI

struct DockerProjectsView: View {
    @Bindable var vm: DockerProjectsViewModel
    @State private var order = [KeyPathComparator(\DockerProject.name)]
    @State private var selection: DockerProject.ID?
    @State private var detailsProject: DockerProject?
    @State private var pendingClean: DockerProject?
    @State private var pendingDelete: DockerProject?
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await load(announce: false)
                focusContent = true
            }
            .sheet(item: $vm.actionReport) { report in
                DockerStreamReportSheet(report: report)
            }
            .sheet(item: $detailsProject) { project in
                DockerProjectDetailsSheet(project: project, vm: vm)
            }
            .confirmationDialog(
                cleanTitle,
                isPresented: Binding(
                    get: { pendingClean != nil },
                    set: { if !$0 { pendingClean = nil } }
                )
            ) {
                Button("containers.project.action.clean", role: .destructive) {
                    guard let project = pendingClean else { return }
                    pendingClean = nil
                    Task { await perform(.clean, on: project) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                if let project = pendingClean {
                    Text(String(
                        localized: "containers.project.clean.confirm.message",
                        defaultValue: "The containers of “\(project.name)” will be stopped and removed. The compose file and its folder are kept, and the project can be started again."
                    ))
                }
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("common.button.delete", role: .destructive) {
                    guard let project = pendingDelete else { return }
                    pendingDelete = nil
                    Task {
                        VoiceOver.announce(await vm.delete(project), priority: .high)
                    }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                if let project = pendingDelete {
                    Text(String(
                        localized: "containers.project.delete.confirm.message",
                        defaultValue: "The project “\(project.name)” and its containers will be removed from Container Manager. This cannot be undone from this app."
                    ))
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.projects.isEmpty {
            ModuleLoadingView("containers.project.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage = vm.errorMessage, vm.projects.isEmpty {
            ModuleErrorView(message: errorMessage) {
                Task { await load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else if vm.projects.isEmpty {
            EmptyModuleView(
                title: "containers.project.empty.title",
                systemImage: "square.stack.3d.up",
                description: "containers.project.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Table(
                    vm.projects.sorted(using: order),
                    selection: $selection,
                    sortOrder: $order
                ) {
                    TableColumn("common.column.name", value: \.name)
                    TableColumn("common.column.state", value: \.status.sortRank) { project in
                        Text(project.status.localizedName)
                    }
                    TableColumn("containers.project.column.containers", value: \.containerCount) { project in
                        Text(project.containerCount.formatted())
                    }
                    TableColumn("common.column.path", value: \.path)
                    TableColumn("containers.project.column.updated", value: \.sortableUpdatedAt) { project in
                        Text(project.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    }
                }
                .accessibilityLabel("containers.tab.projects")
                .accessibilityFocused($focusContent)
                .contextMenu(forSelectionType: DockerProject.ID.self) { ids in
                    if let project = vm.projects.first(where: { ids.contains($0.id) }) {
                        projectActions(project)
                    }
                }

                actionBar

                Text(vm.summary)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(vm.projects.first { $0.id == selection }?.isRunning == true
                   ? "common.button.stop"
                   : "common.button.start") {
                guard let project = selectedProject else { return }
                Task { await perform(project.isRunning ? .stop : .start, on: project) }
            }
            .disabled(selectedProject == nil || selectedIsBusy)
            .help("containers.project.action.toggle.hint")

            Button("containers.action.restart") {
                guard let project = selectedProject else { return }
                Task { await perform(.restart, on: project) }
            }
            .disabled(selectedProject?.isRunning != true || selectedIsBusy)
            .help("containers.project.action.restart.hint")

            Button("containers.project.action.build") {
                guard let project = selectedProject else { return }
                Task { await perform(.build, on: project) }
            }
            .disabled(selectedProject == nil || selectedIsBusy)
            .help("containers.project.action.build.hint")

            Button("containers.project.action.clean") {
                pendingClean = selectedProject
            }
            .disabled(selectedProject == nil || selectedIsBusy)
            .help("containers.project.action.clean.hint")

            Button("common.button.delete", role: .destructive) {
                pendingDelete = selectedProject
            }
            .disabled(selectedProject == nil || selectedIsBusy)
            .help("containers.project.action.delete.hint")

            Button("containers.project.action.details") {
                detailsProject = selectedProject
            }
            .disabled(selectedProject == nil)
            .help("containers.project.action.details.hint")

            if selectedIsBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("containers.project.action.in_progress")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func projectActions(_ project: DockerProject) -> some View {
        if project.isRunning {
            Button("common.button.stop") { Task { await perform(.stop, on: project) } }
            Button("containers.action.restart") { Task { await perform(.restart, on: project) } }
        } else {
            Button("common.button.start") { Task { await perform(.start, on: project) } }
        }
        Button("containers.project.action.build") { Task { await perform(.build, on: project) } }
        Divider()
        Button("containers.project.action.clean") { pendingClean = project }
        Button("common.button.delete", role: .destructive) { pendingDelete = project }
        Divider()
        Button("containers.project.action.details") { detailsProject = project }
    }

    private var selectedProject: DockerProject? {
        vm.projects.first { $0.id == selection }
    }

    private var selectedIsBusy: Bool {
        guard let selectedProject else { return false }
        return vm.busyProjectIDs.contains(selectedProject.id)
    }

    private var cleanTitle: Text {
        Text(String(
            localized: "containers.project.clean.confirm.title",
            defaultValue: "Clean “\(pendingClean?.name ?? "")”?"
        ))
    }

    private var deleteTitle: Text {
        Text(String(
            localized: "containers.project.delete.confirm.title",
            defaultValue: "Delete “\(pendingDelete?.name ?? "")”?"
        ))
    }

    private func load(announce: Bool) async {
        await vm.load()
        guard announce, !Task.isCancelled else { return }
        VoiceOver.announce(vm.summary, category: vm.errorMessage == nil ? .result : .error)
    }

    private func perform(_ action: DockerProjectAction, on project: DockerProject) async {
        VoiceOver.announce(
            String(
                localized: "containers.project.action.started",
                defaultValue: "\(DockerProjectsViewModel.label(for: action)) in progress for \(project.name)…"
            ),
            category: .progress
        )
        VoiceOver.announce(await vm.perform(action, on: project), priority: .high)
    }
}

extension DockerProject {
    /// Missing dates sort together at the far past instead of throwing the column.
    var sortableUpdatedAt: Date { updatedAt ?? .distantPast }
}

/// Full docker-compose output of an action, readable line by line where DSM only flashes it
/// in a terminal emulator.
struct DockerStreamReportSheet: View {
    let report: DockerProjectsViewModel.ActionReport
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusTitle: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(outcomeText)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusTitle)
                    .padding()

                Divider()

                if report.result.lines.isEmpty {
                    EmptyModuleView(
                        title: "containers.project.report.empty.title",
                        systemImage: "text.alignleft",
                        description: "containers.project.report.empty.description"
                    )
                } else {
                    List(Array(report.result.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .accessibilityLabel(String(
                        localized: "containers.project.report.list_label",
                        defaultValue: "Output of \(report.actionLabel) for \(report.projectName)"
                    ))
                }
            }
            .navigationTitle(String(
                localized: "containers.project.report.title",
                defaultValue: "\(report.actionLabel): \(report.projectName)"
            ))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.status.done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .help("common.button.close_information")
                }
            }
        }
        .frame(minWidth: 560, minHeight: 400)
        .task {
            await Task.yield()
            focusTitle = true
        }
    }

    private var outcomeText: String {
        if report.result.succeeded {
            return String(
                localized: "containers.project.report.success",
                defaultValue: "\(report.actionLabel) finished for \(report.projectName)"
            )
        }
        if let exitCode = report.result.exitCode {
            return String(
                localized: "containers.project.report.failure",
                defaultValue: "\(report.actionLabel) failed for \(report.projectName), exit code \(exitCode)"
            )
        }
        return String(
            localized: "containers.project.action.failed",
            defaultValue: "\(report.actionLabel) failed for \(report.projectName)"
        )
    }
}

/// Read-only project details, compose file included.
struct DockerProjectDetailsSheet: View {
    let project: DockerProject
    let vm: DockerProjectsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var composeContent: String?
    @State private var loadErrorMessage: String?
    @AccessibilityFocusState private var focusTitle: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("common.label.information") {
                    LabeledContent("common.column.name", value: project.name)
                    LabeledContent("common.column.state", value: project.status.localizedName)
                    LabeledContent("common.column.path", value: project.path)
                    LabeledContent(
                        "containers.project.column.containers",
                        value: project.containerCount.formatted()
                    )
                    if let created = project.createdAt {
                        LabeledContent(
                            "common.column.creation_date",
                            value: created.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    if let updated = project.updatedAt {
                        LabeledContent(
                            "containers.project.column.updated",
                            value: updated.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }
                if let name = project.servicePortalName, project.isServicePortalEnabled {
                    Section("containers.project.detail.portal") {
                        LabeledContent("common.column.name", value: name)
                        if let port = project.servicePortalPort {
                            LabeledContent("containers.project.detail.port", value: port.formatted(.number.grouping(.never)))
                        }
                        if let scheme = project.servicePortalProtocol {
                            LabeledContent("common.column.protocol", value: scheme)
                        }
                    }
                }
                Section("containers.project.detail.compose") {
                    if let composeContent {
                        Text(composeContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else if let loadErrorMessage {
                        Text(loadErrorMessage)
                            .foregroundStyle(.readableRed)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("containers.project.detail.compose_loading")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(
                localized: "containers.project.detail.title",
                defaultValue: "Project \(project.name)"
            ))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.status.done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .help("common.button.close_information")
                }
            }
        }
        .frame(minWidth: 560, minHeight: 460)
        .task {
            await Task.yield()
            focusTitle = true
            do {
                composeContent = try await vm.projectDetails(id: project.id).content
                    ?? String(localized: "containers.project.detail.compose_missing")
            } catch {
                guard !DSMError.isCancellation(error) else { return }
                loadErrorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
