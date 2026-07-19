//
//  PackageSettingsSheet.swift
//  dsmaccess
//
//  Feuille des réglages globaux du Centre de paquets (SYNO.Core.Package.Setting) : mise à jour
//  automatique, paquets bêta, notifications. Chaque contrôle enregistre immédiatement (comme
//  les bascules de FileServicesView) et annonce le résultat à VoiceOver.
//

import SwiftUI

struct PackageSettingsSheet: View {
    @State private var vm: PackageSettingsViewModel
    @AccessibilityFocusState private var focusTitle: Bool
    @AccessibilityFocusState private var focusStatus: Bool
    @Environment(\.dismiss) private var dismiss

    init(session: SessionStore) {
        _vm = State(initialValue: PackageSettingsViewModel(session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Réglages du Centre de paquets")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            content

            if let error = vm.saveErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityFocused($focusStatus)
            }

            if vm.isSaving {
                ProgressView("Enregistrement des réglages…")
            }

            HStack {
                Spacer()
                Button("Terminé") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.isSaving)
                    .help("Fermer les réglages du Centre de paquets")
            }
        }
        .padding(24)
        .frame(width: 460)
        .task {
            focusTitle = true
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.settings == nil {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Chargement…").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($focusStatus)
        } else if let error = vm.errorMessage, vm.settings == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(error).foregroundStyle(.red)
                Button("Réessayer") { Task { await load() } }
                    .help("Réessayer de charger les réglages du Centre de paquets")
            }
            .accessibilityFocused($focusStatus)
        } else if vm.settings != nil {
            controls
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Mise à jour automatique.
            VStack(alignment: .leading, spacing: 4) {
                Picker("Mise à jour automatique", selection: autoUpdateBinding) {
                    Text("Désactivée").tag(AutoUpdateMode.off)
                    Text("Versions importantes").tag(AutoUpdateMode.important)
                    Text("Dernières versions").tag(AutoUpdateMode.latest)
                }
                .help("Choisir la stratégie de mise à jour automatique des paquets")
                Text("Certains paquets ne prennent pas en charge la mise à jour automatique.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Paquets bêta.
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Afficher les versions bêta", isOn: boolBinding(
                    get: { $0.updateChannelBeta },
                    set: { await vm.setBeta($0) }
                ))
                .help("Afficher les versions bêta dans le Centre de paquets")
                Text("Les versions bêta permettent d'essayer les nouvelles fonctionnalités avant leur publication officielle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Notifications.
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications de mise à jour")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Toggle("Activer les notifications sur le bureau", isOn: boolBinding(
                    get: { $0.enableDsm },
                    set: { await vm.setDsmNotify($0) }
                ))
                .help("Activer les notifications de mise à jour sur le bureau")
                Toggle("Activer la notification par courriel", isOn: boolBinding(
                    get: { $0.enableEmail },
                    set: { await vm.setEmailNotify($0) }
                ))
                .help("Activer les notifications de mise à jour par courriel")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Paramètres conservés")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let settings = vm.settings {
                    LabeledContent("Volume par défaut", value: settings.defaultVol)
                    LabeledContent("Niveau de confiance (code DSM)") {
                        Text(settings.trustLevel, format: .number.grouping(.never))
                    }
                }
                Text("DSM Access conserve ces valeurs lors de chaque enregistrement. Pour modifier le niveau de confiance, les sources ou les certificats d’éditeur, utilisez le Centre de paquets DSM : ce NAS ne permet pas à DSM Access de les gérer en toute sécurité.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(vm.isSaving)
    }

    // MARK: - Bindings

    private var autoUpdateBinding: Binding<AutoUpdateMode> {
        Binding(
            get: { vm.settings?.autoUpdateMode ?? .off },
            set: { mode in
                Task {
                    let msg = await vm.setAutoUpdateMode(mode)
                    VoiceOver.announce(msg, priority: .high)
                }
            }
        )
    }

    /// Fabrique un Binding<Bool> qui lit un champ des réglages et enregistre via `set`.
    private func boolBinding(get: @escaping (PackageSettings) -> Bool,
                             set: @escaping (Bool) async -> DSMOperationOutcome) -> Binding<Bool> {
        Binding(
            get: { vm.settings.map(get) ?? false },
            set: { newValue in
                Task {
                    let msg = await set(newValue)
                    VoiceOver.announce(msg, priority: .high)
                }
            }
        )
    }

    private var loadAnnouncement: String {
        if let error = vm.errorMessage { return error }
        return String(localized: "Réglages du Centre de paquets chargés")
    }

    private func load() async {
        await vm.load()
        guard !Task.isCancelled else { return }
        if vm.errorMessage != nil { focusStatus = true }
        VoiceOver.announce(
            loadAnnouncement,
            category: vm.errorMessage == nil ? .result : .error
        )
    }
}
