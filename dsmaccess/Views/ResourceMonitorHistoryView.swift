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
            ModuleLoadingView("Chargement de l’historique…")
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

                Text("Historique des alertes")
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
                TableColumn("Date", value: \.sortableDate) { entry in
                    Text(vm.dateText(for: entry))
                }
                // Trié par gravité et non par ordre alphabétique : « Critique » doit se
                // ranger après « Avertissement », pas avant.
                TableColumn("Niveau", value: \.sortableLevel) { entry in
                    Text(vm.levelText(for: entry))
                        .foregroundStyle(color(for: entry.level))
                }
                TableColumn("Alerte", value: \.sortableEvent) { entry in
                    Text(vm.eventText(for: entry))
                }
            }

            if vm.isTruncated {
                Text("\(vm.entries.count) alertes affichées sur \(vm.totalCount) enregistrées.")
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
                title: "Aucune alerte enregistrée",
                systemImage: "clock.badge.xmark",
                description: "L’enregistrement de l’historique est désactivé sur le NAS : aucune alerte n’y est consignée. Activez-le ci-dessous pour que les prochaines le soient."
            )
            .accessibilityFocused($focusContent)
        } else if vm.alarmRuleCount == 0 {
            EmptyModuleView(
                title: "Aucune alerte enregistrée",
                systemImage: "bell.slash",
                description: "L’enregistrement est actif, mais aucune règle n’est définie dans l’alarme des performances : le NAS n’a aucun seuil à surveiller et ne consignera rien. Ce journal restera vide tant qu’aucune règle n’existe."
            )
            .accessibilityFocused($focusContent)
        } else {
            EmptyModuleView(
                title: "Aucune alerte enregistrée",
                systemImage: "clock",
                description: "Le NAS n’a consigné aucune alerte depuis l’activation de l’enregistrement. Une alerte y apparaît quand une ressource franchit un seuil défini dans l’alarme des performances."
            )
            .accessibilityFocused($focusContent)
        }
    }

    private var recordingSetting: some View {
        Toggle(
            "Enregistrer l’historique",
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
        .accessibilityHint("Le NAS consigne les alertes de ressources tant que ce réglage est actif")
        .help("Consigner les alertes de ressources dans l’historique du NAS")
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
