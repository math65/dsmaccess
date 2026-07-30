//
//  ResourceMonitorHistoryView.swift
//  dsmaccess
//
//  Onglet Historique du moniteur de ressources, en tableau triable comme les autres onglets
//  du module. Un tableau et non une courbe : une série de points tracés ne dit rien à un
//  lecteur d'écran, là où des lignes datées se parcourent et se trient.
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
            // L'interrupteur d'enregistrement reste accessible dans tous les états, y compris
            // quand le journal est vide : c'est précisément là qu'il sert.
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
                // Trié par gravité et non par ordre alphabétique : « Critique » doit se
                // ranger après « Avertissement », pas avant.
                TableColumn("common.column.level", value: \.sortableLevel) { entry in
                    Text(vm.levelText(for: entry))
                        .foregroundStyle(color(for: entry.level))
                }
                TableColumn("common.level.alert", value: \.sortableEvent) { entry in
                    Text(vm.eventText(for: entry))
                }
            }

            if vm.isTruncated {
                Text(String(localized: "monitor.history.count.filtered.footer", defaultValue: "\(vm.entries.count) of \(vm.totalCount) recorded alerts shown."))
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
            }
        }
    }

    /// Trois vides très différents, qu'un message unique confondrait en laissant croire à un
    /// NAS irréprochable : l'enregistrement est coupé, aucune règle ne peut rien détecter, ou
    /// rien n'a franchi de seuil.
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
                        VoiceOver.announce(outcome, priority: .high)
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

    /// La couleur double le mot, elle ne le remplace pas : le niveau est toujours écrit.
    private func color(for level: ResourceMonitorLogEntry.Level) -> Color {
        switch level {
        case .critical: .readableRed
        case .warning: .readableOrange
        case .information, .other: .primary
        }
    }
}
