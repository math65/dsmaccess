//
//  PerformanceAlarmView.swift
//  dsmaccess
//
//  Onglet Alarme des performances : les règles qui décident de ce que le NAS consigne dans
//  son historique. Tableau triable comme les autres onglets du module.
//

import SwiftUI

struct PerformanceAlarmView: View {
    @Bindable var vm: PerformanceAlarmViewModel
    @State private var order = [
        KeyPathComparator(\PerformanceAlarmRule.sortableSeverity, order: .reverse)
    ]
    @State private var selection: Set<PerformanceAlarmRule.ID> = []
    @State private var draft: PerformanceAlarmRuleDraft?
    @State private var pendingDeletion: [PerformanceAlarmRule] = []
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await vm.load()
                focusContent = true
            }
            .sheet(item: $draft) { editing in
                PerformanceAlarmRuleSheet(vm: vm, draft: editing) { saved in
                    draft = nil
                    guard let saved else { return }
                    Task {
                        let outcome = await vm.save(saved)
                        VoiceOver.announce(outcome, priority: .high)
                    }
                }
            }
            .confirmationDialog(
                deletionTitle,
                isPresented: Binding(
                    get: { !pendingDeletion.isEmpty },
                    set: { if !$0 { pendingDeletion = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button("common.button.delete", role: .destructive) {
                    let doomed = pendingDeletion
                    pendingDeletion = []
                    Task {
                        let outcome = await vm.delete(doomed)
                        VoiceOver.announce(outcome, priority: .high)
                    }
                }
                Button("common.button.cancel", role: .cancel) { pendingDeletion = [] }
            } message: {
                Text(deletionConsequence)
            }
    }

    private var deletionTitle: String {
        if pendingDeletion.count == 1, let only = pendingDeletion.first {
            return String(localized: "alarm.rule.delete.confirm.title", defaultValue: "Delete the rule “\(vm.description(of: only))”?")
        }
        return String(localized: "alarm.rules.delete.confirm.title", defaultValue: "Delete \(pendingDeletion.count) rules?")
    }

    private var deletionConsequence: String {
        if pendingDeletion.count == 1 {
            return String(localized: "alarm.rule.delete.confirm.message")
        }
        return String(localized: "alarm.rules.delete.confirm.message")
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.rules.isEmpty {
            ModuleLoadingView("alarm.rules.loading")
                .accessibilityFocused($focusContent)
        } else if let error = vm.errorMessage, vm.rules.isEmpty {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.readableRed)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                Text("alarm.rules.title")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityFocused($focusContent)

                if vm.rules.isEmpty {
                    EmptyModuleView(
                        title: "common.empty.alarm_rules",
                        systemImage: "bell.slash",
                        description: "alarm.rules.empty.description"
                    )
                    .accessibilityFocused($focusContent)
                } else {
                    table
                }

                commands
            }
        }
    }

    private var table: some View {
        Table(vm.rules.sorted(using: order), selection: $selection, sortOrder: $order) {
            TableColumn("alarm.rules.column.rule", value: \.sortableTarget) { rule in
                Text(vm.description(of: rule))
            }
            TableColumn("common.column.kind", value: \.sortableKind) { rule in
                Text(vm.kindText(rule.kind))
            }
            // Triée par gravité et non par ordre alphabétique : « Critique » doit se ranger
            // après « Avertissement ».
            TableColumn("common.column.severity", value: \.sortableSeverity) { rule in
                Text(vm.severityText(rule.severity))
                    .foregroundStyle(rule.severity == .critical ? .readableRed : .readableOrange)
            }
            // L'état s'écrit en toutes lettres : un interrupteur seul ne dirait rien à qui
            // parcourt le tableau colonne par colonne.
            TableColumn("common.column.state", value: \.sortableEnabled) { rule in
                Toggle(
                    isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in
                            Task {
                                let outcome = await vm.setEnabled(rule, enabled)
                                VoiceOver.announce(outcome, priority: .high)
                            }
                        }
                    )
                ) {
                    Text(rule.isEnabled ? "alarm.rule.state.active" : "alarm.rule.state.inactive")
                }
                .toggleStyle(.checkbox)
                .disabled(vm.isBusy(rule))
                .accessibilityLabel(Text(String(localized: "alarm.rule.toggle.label", defaultValue: "Turn on the rule \(vm.description(of: rule))")))
            }
        }
    }

    private var commands: some View {
        HStack(spacing: 12) {
            Button("alarm.rules.add.button") {
                draft = PerformanceAlarmRuleDraft()
            }
            .help("alarm.rules.add.hint")

            Button("common.button.edit") {
                guard let rule = selectedRules.first else { return }
                draft = PerformanceAlarmRuleDraft(editing: rule)
            }
            .disabled(selectedRules.count != 1 || !vm.canModify(selectedRules[0]))
            .help("alarm.rules.edit.button")

            Button("common.button.delete", role: .destructive) {
                pendingDeletion = selectedRules
            }
            .disabled(selectedRules.isEmpty)
            .help("alarm.rules.delete.button")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var selectedRules: [PerformanceAlarmRule] {
        vm.rules.filter { selection.contains($0.id) }
    }
}

/// `sheet(item:)` a besoin d'une identité : celle de la règle modifiée, ou une valeur fixe
/// pour la création, qui n'en a pas encore.
extension PerformanceAlarmRuleDraft: Identifiable {
    var id: String { ruleID ?? "creation" }
}
