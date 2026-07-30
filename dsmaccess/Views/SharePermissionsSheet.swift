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
                        .accessibilityLabel("share_permissions.save.progress")
                }
                Spacer()
                // Sans modification, « Annuler » laisserait croire qu'on revient sur quelque
                // chose — la création du compte, quand l'écran s'ouvre juste après elle.
                if viewModel.hasChanges {
                    Button("common.button.cancel", role: .cancel) { showsDiscardConfirmation = true }
                        .keyboardShortcut(.cancelAction)
                        .help("share_permissions.close.hint")
                    Button("common.button.save") {
                        Task {
                            let outcome = await viewModel.save()
                            onFinish(outcome)
                            if case .success = outcome { dismiss() }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.isSaving)
                    .help("share_permissions.save.button")
                } else {
                    Button("common.button.close", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .help("share_permissions.close.button")
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
            "share_permissions.discard.confirm.title",
            isPresented: $showsDiscardConfirmation
        ) {
            Button("share_permissions.discard.confirm.button", role: .destructive) { dismiss() }
            Button("share_permissions.discard.cancel.button", role: .cancel) { }
        } message: {
            Text("share_permissions.discard.confirm.message")
        }
    }

    private var title: String {
        switch viewModel.holder {
        case .user(let name): return String(localized: "share_permissions.user.title", defaultValue: "Permissions for \(name)")
        case .group(let name): return String(localized: "share_permissions.group.title", defaultValue: "Permissions for the \(name) group")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ModuleLoadingView("share_permissions.loading")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) {
                Task { await viewModel.load() }
            }
            .accessibilityFocused($contentFocused)
        } else if viewModel.permissions.isEmpty {
            EmptyModuleView(
                title: "common.empty.shared_folders",
                systemImage: "folder",
                description: "share_permissions.folders.empty.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            TabView {
                shareTab
                    .tabItem { Text("common.module.shared_folders") }
                applicationTab
                    .tabItem { Text("common.label.applications") }
                if viewModel.editsMemberships {
                    groupTab
                        .tabItem { Text("common.label.groups") }
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
                Text("share_permissions.folders.description")
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
                title: "common.empty.groups",
                systemImage: "person.3",
                description: "share_permissions.groups.empty.description"
            )
        } else {
            Form {
                Section("common.label.groups") {
                    ForEach(viewModel.groups) { group in
                        Toggle(group.name, isOn: membershipBinding(group))
                            .disabled(viewModel.isSaving)
                            .help(String(localized: "share_permissions.group_membership.hint", defaultValue: "Make this account a member of the \(group.name) group"))
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
                    title: "share_permissions.applications.empty.title",
                    systemImage: "square.grid.2x2",
                    description: "share_permissions.applications.empty.description"
                )
            } else {
                ApplicationPrivilegeTableView(
                    privileges: viewModel.applications,
                    isEnabled: !viewModel.isSaving
                ) { application, decision in
                    viewModel.setDecision(decision, for: application)
                }
                Text("share_permissions.applications.description")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }
}
