//
//  SharePermissionsSheet.swift
//  dsmaccess
//
//  Permissions d'un compte sur les dossiers partagés, présentées comme la grille de DSM.
//

import SwiftUI

struct SharePermissionsSheet: View {
    @State private var viewModel: SharePermissionsViewModel
    @State private var showsDiscardConfirmation = false
    @AccessibilityFocusState private var contentFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let onFinish: (DSMOperationOutcome) -> Void

    init(
        holder: DSMPermissionHolder,
        session: SessionStore,
        onFinish: @escaping (DSMOperationOutcome) -> Void
    ) {
        _viewModel = State(initialValue: SharePermissionsViewModel(holder: holder, session: session))
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            content

            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Enregistrement en cours")
                }
                Spacer()
                // Sans modification, « Annuler » laisserait croire qu'on revient sur quelque
                // chose — la création du compte, quand l'écran s'ouvre juste après elle.
                if viewModel.hasChanges {
                    Button("Annuler", role: .cancel) { showsDiscardConfirmation = true }
                        .keyboardShortcut(.cancelAction)
                        .help("Fermer sans enregistrer les modifications")
                    Button("Enregistrer") {
                        Task {
                            let outcome = await viewModel.save()
                            onFinish(outcome)
                            if case .success = outcome { dismiss() }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isSaving)
                    .help("Enregistrer les permissions modifiées")
                } else {
                    Button("Fermer", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .help("Fermer les permissions")
                }
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
        .task {
            await viewModel.load()
            contentFocused = true
        }
        .confirmationDialog(
            "Abandonner les modifications ?",
            isPresented: $showsDiscardConfirmation
        ) {
            Button("Abandonner", role: .destructive) { dismiss() }
            Button("Continuer la modification", role: .cancel) { }
        } message: {
            Text("Les permissions modifiées ne seront pas enregistrées sur le NAS.")
        }
    }

    private var title: String {
        switch viewModel.holder {
        case .user(let name): return String(localized: "Permissions de \(name)")
        case .group(let name): return String(localized: "Permissions du groupe \(name)")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ModuleLoadingView("Chargement des permissions…")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) {
                Task { await viewModel.load() }
            }
            .accessibilityFocused($contentFocused)
        } else if viewModel.permissions.isEmpty {
            EmptyModuleView(
                title: "Aucun dossier partagé",
                systemImage: "folder",
                description: "Ce NAS n’expose aucun dossier partagé à autoriser."
            )
            .accessibilityFocused($contentFocused)
        } else {
            TabView {
                shareTab
                    .tabItem { Text("Dossiers partagés") }
                applicationTab
                    .tabItem { Text("Applications") }
                if viewModel.editsMemberships {
                    groupTab
                        .tabItem { Text("Groupes") }
                }
            }
        }
    }

    private var shareTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            SharePermissionTableView(
                permissions: viewModel.permissions,
                holder: viewModel.holder,
                isEnabled: !viewModel.isSaving
            ) { share, level in
                viewModel.setLevel(level, for: share)
            }
            .accessibilityFocused($contentFocused)

            if viewModel.holder.inheritsFromGroups {
                Text("Entre le droit du compte et celui de ses groupes : un aucun accès l’emporte sur tout, sinon c’est le droit le plus large qui s’applique. Un compte en lecture/écriture dans un groupe en lecture seule peut donc écrire.")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    /// Même présentation que la liste de groupes du formulaire de création : une case par
    /// groupe, cochée quand le compte en fait partie.
    @ViewBuilder
    private var groupTab: some View {
        if viewModel.groups.isEmpty {
            EmptyModuleView(
                title: "Aucun groupe",
                systemImage: "person.3",
                description: "Créez un groupe pour donner les mêmes accès à plusieurs comptes."
            )
        } else {
            Form {
                Section("Groupes") {
                    ForEach(viewModel.groups) { group in
                        Toggle(group.name, isOn: membershipBinding(group))
                            .disabled(viewModel.isSaving)
                            .help("Faire appartenir ce compte au groupe \(group.name)")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func membershipBinding(_ group: DSMGroup) -> Binding<Bool> {
        Binding(
            get: { viewModel.memberships.contains(group.name) },
            set: { viewModel.setMembership($0, of: group) }
        )
    }

    @ViewBuilder
    private var applicationTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let applicationsUnavailable = viewModel.applicationsUnavailable {
                ModuleErrorView(message: applicationsUnavailable) {
                    Task { await viewModel.load() }
                }
            } else if viewModel.applications.isEmpty {
                EmptyModuleView(
                    title: "Aucune application",
                    systemImage: "square.grid.2x2",
                    description: "Ce NAS n’expose aucune application soumise à autorisation."
                )
            } else {
                ApplicationPrivilegeTableView(
                    privileges: viewModel.applications,
                    isEnabled: !viewModel.isSaving
                ) { application, decision in
                    viewModel.setDecision(decision, for: application)
                }
                Text("Un refus l’emporte sur toute autorisation, y compris celle d’un groupe. Une application laissée sur « par défaut » suit le réglage du NAS.")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }
}
