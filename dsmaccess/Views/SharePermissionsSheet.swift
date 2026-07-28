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
        userName: String,
        session: SessionStore,
        onFinish: @escaping (DSMOperationOutcome) -> Void
    ) {
        _viewModel = State(initialValue: SharePermissionsViewModel(userName: userName, session: session))
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions de \(viewModel.userName)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            content

            Text("En cas de conflit entre les droits du compte et ceux de ses groupes, DSM retient le plus restrictif : aucun accès l’emporte sur lecture/écriture, qui l’emporte sur lecture seule.")
                .font(.caption)
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)

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
                isEnabled: !viewModel.isSaving
            ) { share, level in
                viewModel.setLevel(level, for: share)
            }
            .accessibilityFocused($contentFocused)
        }
    }
}
