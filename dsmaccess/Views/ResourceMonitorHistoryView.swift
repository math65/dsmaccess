//
//  ResourceMonitorHistoryView.swift
//  dsmaccess
//
//  History tab of the resource monitor, as a sortable table like the module's other tabs.
//  A table and not a curve: a series of plotted points says nothing to a screen reader,
//  whereas dated rows can be browsed and sorted.
//

import SwiftUI

struct ResourceMonitorHistoryView: View {
    @Bindable var vm: ResourceMonitorHistoryViewModel
    @State private var order = [
        KeyPathComparator(\ResourceMonitorLogEntry.sortableDate, order: .reverse)
    ]
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await vm.load()
                focusContent = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.entries.isEmpty {
            ModuleLoadingView("monitor.history.loading")
                .accessibilityFocused($focusContent)
        } else if let error = vm.errorMessage, vm.entries.isEmpty {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else {
            // The recording switch stays reachable in every state, including when the log is
            // empty: that is exactly where it is useful.
            VStack(alignment: .leading, spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.readableRed)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                Text("monitor.history.title")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityFocused($focusContent)

                if vm.entries.isEmpty {
                    emptyState
                } else {
                    table
                }

                recordingSetting
            }
        }
    }

    private var table: some View {
        VStack(alignment: .leading, spacing: 0) {
            Table(vm.entries.sorted(using: order), sortOrder: $order) {
                TableColumn("common.column.date", value: \.sortableDate) { entry in
                    Text(vm.dateText(for: entry))
                }
                // Sorted by severity and not alphabetically: "Critical" must come after
                // "Warning", not before.
                TableColumn("common.column.level", value: \.sortableLevel) { entry in
                    Text(vm.levelText(for: entry))
                        .foregroundStyle(color(for: entry.level))
                }
                TableColumn("common.level.alert", value: \.sortableEvent) { entry in
                    Text(vm.eventText(for: entry))
                }
            }
            .accessibilityLabel("monitor.history.title")

            if vm.isTruncated {
                Text(String(localized: "monitor.history.count.filtered.footer", defaultValue: "\(vm.entries.count) of \(vm.totalCount) recorded alerts shown."))
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
        }
    }

    /// Three very different kinds of emptiness, which a single message would conflate into
    /// the impression of a faultless NAS: recording is off, no rule can detect anything, or
    /// nothing has crossed a threshold.
    @ViewBuilder
    private var emptyState: some View {
        if vm.historyEnabled == false {
            EmptyModuleView(
                title: "monitor.history.empty.title",
                systemImage: "clock.badge.xmark",
                description: "monitor.history.empty.recording_off.description"
            )
            .accessibilityFocused($focusContent)
        } else if vm.alarmRuleCount == 0 {
            EmptyModuleView(
                title: "monitor.history.empty.title",
                systemImage: "bell.slash",
                description: "monitor.history.empty.no_rule.description"
            )
            .accessibilityFocused($focusContent)
        } else {
            EmptyModuleView(
                title: "monitor.history.empty.title",
                systemImage: "clock",
                description: "monitor.history.empty.description"
            )
            .accessibilityFocused($focusContent)
        }
    }

    private var recordingSetting: some View {
        Toggle(
            "monitor.history.recording.label",
            isOn: Binding(
                get: { vm.historyEnabled ?? false },
                set: { enabled in
                    Task {
                        let outcome = await vm.setHistoryEnabled(enabled)
                        OperationFailures.shared.present(outcome, from: .resourceMonitor)
                    }
                }
            )
        )
        .disabled(vm.isUpdatingSetting || vm.historyEnabled == nil)
        .accessibilityHint("monitor.history.recording.footer")
        .help("monitor.history.recording.hint")
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The colour backs up the word, it does not replace it: the level is always written out.
    private func color(for level: ResourceMonitorLogEntry.Level) -> Color {
        switch level {
        case .critical: .readableRed
        case .warning: .readableOrange
        case .information, .other: .primary
        }
    }
}
