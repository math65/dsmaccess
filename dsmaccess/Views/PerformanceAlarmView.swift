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
                Button("Supprimer", role: .destructive) {
                    let doomed = pendingDeletion
                    pendingDeletion = []
                    Task {
                        let outcome = await vm.delete(doomed)
                        VoiceOver.announce(outcome, priority: .high)
                    }
                }
                Button("Annuler", role: .cancel) { pendingDeletion = [] }
            } message: {
                Text(deletionConsequence)
            }
    }

    private var deletionTitle: String {
        if pendingDeletion.count == 1, let only = pendingDeletion.first {
            return String(localized: "Supprimer la règle « \(vm.description(of: only)) » ?")
        }
        return String(localized: "Supprimer \(pendingDeletion.count) règles ?")
    }

    private var deletionConsequence: String {
        if pendingDeletion.count == 1 {
            return String(localized: "Le NAS cessera de surveiller ce seuil. Les alertes déjà consignées dans l’historique sont conservées.")
        }
        return String(localized: "Le NAS cessera de surveiller ces seuils. Les alertes déjà consignées dans l’historique sont conservées.")
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.rules.isEmpty {
            ModuleLoadingView("Chargement des règles d’alarme…")
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

                Text("Règles d’alarme")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityFocused($focusContent)

                if vm.rules.isEmpty {
                    EmptyModuleView(
                        title: "Aucune règle d’alarme",
                        systemImage: "bell.slash",
                        description: "Le NAS ne surveille aucun seuil et ne consignera donc aucune alerte. Ajoutez une règle pour qu’il signale une ressource qui dérape."
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
            TableColumn("Règle", value: \.sortableTarget) { rule in
                Text(vm.description(of: rule))
            }
            TableColumn("Type", value: \.sortableKind) { rule in
                Text(vm.kindText(rule.kind))
            }
            // Triée par gravité et non par ordre alphabétique : « Critique » doit se ranger
            // après « Avertissement ».
            TableColumn("Gravité", value: \.sortableSeverity) { rule in
                Text(vm.severityText(rule.severity))
                    .foregroundStyle(rule.severity == .critical ? .readableRed : .readableOrange)
            }
            // L'état s'écrit en toutes lettres : un interrupteur seul ne dirait rien à qui
            // parcourt le tableau colonne par colonne.
            TableColumn("État", value: \.sortableEnabled) { rule in
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
                    Text(rule.isEnabled ? "Active" : "Inactive")
                }
                .toggleStyle(.checkbox)
                .disabled(vm.isBusy(rule))
                .accessibilityLabel(Text("Activer la règle \(vm.description(of: rule))"))
            }
        }
    }

    private var commands: some View {
        HStack(spacing: 12) {
            Button("Ajouter une règle") {
                draft = PerformanceAlarmRuleDraft()
            }
            .help("Composer une nouvelle règle d’alarme")

            Button("Modifier") {
                guard let rule = selectedRules.first else { return }
                draft = PerformanceAlarmRuleDraft(editing: rule)
            }
            .disabled(selectedRules.count != 1 || !vm.canModify(selectedRules[0]))
            .help("Modifier la règle sélectionnée")

            Button("Supprimer", role: .destructive) {
                pendingDeletion = selectedRules
            }
            .disabled(selectedRules.isEmpty)
            .help("Supprimer les règles sélectionnées")

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
