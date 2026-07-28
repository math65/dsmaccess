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
        holder: DSMShareHolder,
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

            if viewModel.holder.inheritsFromGroups {
                Text("Entre le droit du compte et celui de ses groupes : un aucun accès l’emporte sur tout, sinon c’est le droit le plus large qui s’applique. Un compte en lecture/écriture dans un groupe en lecture seule peut donc écrire.")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Enregistrement en cours")
                }
                Spacer()
                Button("Annuler", role: .cancel) {
                    if viewModel.hasChanges {
                        showsDiscardConfirmation = true
                    } else {
                        dismiss()
                    }
                }
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
                .disabled(!viewModel.hasChanges || viewModel.isSaving)
                .help("Enregistrer les permissions modifiées")
            }
        }
        .padding(20)
        .frame(width: 720, height: 520)
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
            SharePermissionTableView(
                permissions: viewModel.permissions,
                holder: viewModel.holder,
                isEnabled: !viewModel.isSaving
            ) { share, level in
                viewModel.setLevel(level, for: share)
            }
            .accessibilityFocused($contentFocused)
        }
    }
}
