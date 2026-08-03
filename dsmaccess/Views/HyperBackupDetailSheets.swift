//
//  HyperBackupDetailSheets.swift
//  dsmaccess
//
//  Versions kept by a backup task, what its destination supports, and the task log.
//

import SwiftUI

struct HyperBackupVersionsSheet: View {
    let task: HyperBackupTask?
    let loadDetails: () async throws -> HyperBackupTaskDetails

    @State private var details: HyperBackupTaskDetails?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var order = [KeyPathComparator(\HyperBackupVersion.sortableCompletion, order: .reverse)]
    @AccessibilityFocusState private var focusContent: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(task?.name ?? String(localized: "hyper_backup.versions.title"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.button.close", role: .cancel) { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
        }
        .frame(minWidth: 680, minHeight: 520)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ModuleLoadingView("hyper_backup.versions.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($focusContent)
        } else if let details {
            TabView {
                versionsTab(details)
                    .tabItem { Text("hyper_backup.versions.tab") }
                destinationTab(details)
                    .tabItem { Text("hyper_backup.destination.tab") }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func versionsTab(_ details: HyperBackupTaskDetails) -> some View {
        if details.versions.isEmpty {
            EmptyModuleView(
                title: "hyper_backup.versions.empty.title",
                systemImage: "clock.arrow.circlepath",
                description: "hyper_backup.versions.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else {
            Table(details.versions.sorted(using: order), sortOrder: $order) {
                TableColumn("hyper_backup.versions.column.completed", value: \.sortableCompletion) { version in
                    Text(dateText(version.completionDate))
                }
                TableColumn("common.column.state", value: \.sortableStatus) { version in
                    Text(version.statusDescription)
                }
                TableColumn("hyper_backup.versions.column.duration") { version in
                    Text(version.durationDescription)
                }
                TableColumn("hyper_backup.versions.column.lock", value: \.sortableLock) { version in
                    Text(version.lockDescription)
                }
            }
            .accessibilityLabel("hyper_backup.versions.table.label")
            .accessibilityFocused($focusContent)
        }
    }

    private func destinationTab(_ details: HyperBackupTaskDetails) -> some View {
        Form {
            Section("hyper_backup.destination.section") {
                if let task {
                    LabeledContent("common.column.destination", value: task.destinationDescription)
                }
                if let hostName = details.target.hostName, !hostName.isEmpty {
                    LabeledContent("hyper_backup.destination.host", value: hostName)
                }
                if let formatType = details.target.formatType, !formatType.isEmpty {
                    LabeledContent("hyper_backup.destination.format", value: formatType)
                }
                LabeledContent(
                    "hyper_backup.destination.encryption",
                    value: details.target.isEncrypted
                        ? String(localized: "hyper_backup.task.encryption.encrypted")
                        : String(localized: "hyper_backup.task.encryption.plain")
                )
                LabeledContent(
                    "hyper_backup.destination.compression",
                    value: details.target.isCompressed
                        ? String(localized: "common.status.enabled.feminine")
                        : String(localized: "common.status.disabled.feminine")
                )
                LabeledContent(
                    "hyper_backup.destination.multi_version",
                    value: details.target.supportsMultipleVersions
                        ? String(localized: "common.answer.yes")
                        : String(localized: "common.answer.no")
                )
                LabeledContent(
                    "hyper_backup.destination.last_integrity_check",
                    value: dateText(details.target.lastIntegrityCheckDate)
                )
            }
            .labeledContentStyle(.readable)

            if let statistics = details.statistics, let latest = statistics.latestRun {
                Section("hyper_backup.statistics.section") {
                    LabeledContent(
                        "hyper_backup.statistics.completed",
                        value: dateText(latest.endDate)
                    )
                    LabeledContent(
                        "hyper_backup.statistics.new_files",
                        value: latest.newCount.formatted()
                    )
                    LabeledContent(
                        "hyper_backup.statistics.modified_files",
                        value: latest.modifiedCount.formatted()
                    )
                    LabeledContent(
                        "hyper_backup.statistics.deleted_files",
                        value: latest.deletedCount.formatted()
                    )
                    LabeledContent(
                        "hyper_backup.statistics.source_size",
                        value: latest.sourceSize.formatted(.byteCount(style: .file))
                    )
                    LabeledContent(
                        "hyper_backup.statistics.target_size",
                        value: latest.targetSize.formatted(.byteCount(style: .file))
                    )
                }
                .labeledContentStyle(.readable)
            } else if details.target.capability?.supportsStatistics == false {
                Section("hyper_backup.statistics.section") {
                    Text("hyper_backup.statistics.unsupported")
                        .foregroundStyle(.readableSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityLabel("hyper_backup.destination.region.label")
        .accessibilityFocused($focusContent)
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return String(localized: "common.value.not_available") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            details = try await loadDetails()
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        guard !Task.isCancelled else { return }
        focusContent = true
    }
}

struct HyperBackupLogSheet: View {
    let task: HyperBackupTask?
    let loadLogs: () async throws -> HyperBackupLogPage

    @State private var page: HyperBackupLogPage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var order = [KeyPathComparator(\HyperBackupLogEntry.sortableTime, order: .reverse)]
    @AccessibilityFocusState private var focusContent: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(task?.name ?? String(localized: "hyper_backup.log.title"))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.button.close", role: .cancel) { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .safeAreaInset(edge: .bottom) { summaryBar }
        }
        .frame(minWidth: 720, minHeight: 520)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ModuleLoadingView("hyper_backup.log.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($focusContent)
        } else if let page, page.entries.isEmpty {
            EmptyModuleView(
                title: "hyper_backup.log.empty.title",
                systemImage: "list.bullet.rectangle",
                description: "hyper_backup.log.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else if let page {
            Table(page.entries.sorted(using: order), sortOrder: $order) {
                TableColumn("common.column.time", value: \.sortableTime) { entry in
                    Text(entry.timeDescription)
                }
                TableColumn("hyper_backup.log.column.level", value: \.sortableLevel) { entry in
                    Text(entry.levelDescription)
                }
                TableColumn("hyper_backup.log.column.event", value: \.event) { entry in
                    Text(entry.event)
                }
                TableColumn("common.column.user") { entry in
                    Text(entry.user ?? String(localized: "common.value.not_available"))
                }
            }
            .accessibilityLabel("hyper_backup.log.table.label")
            .accessibilityFocused($focusContent)
        }
    }

    @ViewBuilder
    private var summaryBar: some View {
        if let page {
            Text(summary(page))
                .font(.caption)
                .foregroundStyle(.readableSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
        }
    }

    private func summary(_ page: HyperBackupLogPage) -> String {
        String(localized: "hyper_backup.log.summary", defaultValue: "\(page.total) entries, \(page.errorCount) errors, \(page.warningCount) warnings")
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            page = try await loadLogs()
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        guard !Task.isCancelled else { return }
        focusContent = true
    }
}
