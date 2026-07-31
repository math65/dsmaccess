//
//  DockerLogView.swift
//  dsmaccess
//
//  “Log” tab of the Containers module: Container Manager's own event log, with the level
//  filter and keyword search applied by the NAS, export to a file, and clearing.
//

import SwiftUI

struct DockerLogView: View {
    @Bindable var vm: DockerLogViewModel
    @State private var selection: DockerLogEntry.ID?
    @State private var isConfirmingClear = false
    @AccessibilityFocusState private var focusContent: Bool
    /// Whether this tab is the selected one; its search field is window-level.
    let isActive: Bool

    var body: some View {
        searchableContent
            .task {
                await load(announce: false)
                focusContent = true
            }
            .task(id: vm.searchText) {
                // Server-side search: let the typing settle before asking the NAS.
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await vm.load(silently: true)
            }
            .confirmationDialog(
                "containers.log.clear.confirm.title",
                isPresented: $isConfirmingClear
            ) {
                Button("containers.log.clear", role: .destructive) {
                    Task { VoiceOver.announce(await vm.clear(), priority: .high) }
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                Text("containers.log.clear.confirm.message")
            }
    }

    @ViewBuilder
    private var searchableContent: some View {
        if isActive {
            content.searchable(text: $vm.searchText, prompt: "containers.log.search.prompt")
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.entries.isEmpty {
            ModuleLoadingView("common.status.loading_log")
                .accessibilityFocused($focusContent)
        } else if let errorMessage = vm.errorMessage, vm.entries.isEmpty {
            ModuleErrorView(message: errorMessage) {
                Task { await load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                filterBar

                if vm.entries.isEmpty {
                    EmptyModuleView(
                        title: "containers.log.module_empty.title",
                        systemImage: "text.alignleft",
                        description: "containers.log.module_empty.description"
                    )
                    .accessibilityFocused($focusContent)
                } else {
                    Table(vm.entries, selection: $selection) {
                        TableColumn("logs.column.time") { entry in
                            Text(entry.time)
                        }
                        TableColumn("common.column.level") { entry in
                            Text(entry.localizedLevel)
                        }
                        TableColumn("common.column.user") { entry in
                            Text(entry.user ?? "—")
                        }
                        TableColumn("containers.log.column.event") { entry in
                            Text(entry.event)
                        }
                    }
                    .accessibilityFocused($focusContent)
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

    private var filterBar: some View {
        HStack {
            Picker("common.column.level", selection: $vm.level) {
                ForEach(DockerLogLevelFilter.allCases) { level in
                    Text(level.localizedName).tag(level)
                }
            }
            .fixedSize()
            .onChange(of: vm.level) {
                Task { await vm.load() }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Menu("logs.export.menu") {
                Button("logs.export.csv") { export(as: .csv) }
                Button("logs.export.html") { export(as: .html) }
            }
            .fixedSize()
            .disabled(vm.isExporting)
            .help("logs.export.hint")

            Button("containers.log.clear", role: .destructive) {
                isConfirmingClear = true
            }
            .disabled(vm.entries.isEmpty)
            .help("containers.log.clear.hint")

            Button("common.button.refresh") {
                Task { await load(announce: true) }
            }
            .help("containers.log.refresh.hint")

            if vm.isExporting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("logs.export.progress")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The export is produced by the NAS then written where the user asks, through the same
    /// system save panel as the system log export.
    private func export(as format: DockerLogExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "container-manager-log.\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.message = String(localized: "logs.export.footer")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        VoiceOver.announce(
            String(localized: "logs.export.progress"),
            category: .progress,
            priority: .low
        )
        Task {
            VoiceOver.announce(await vm.export(format: format, to: url), priority: .high)
        }
    }

    private func load(announce: Bool) async {
        await vm.load()
        guard announce, !Task.isCancelled else { return }
        VoiceOver.announce(vm.summary, category: vm.errorMessage == nil ? .result : .error)
    }
}
