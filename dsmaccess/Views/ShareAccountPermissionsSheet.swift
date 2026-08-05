//
//  ShareAccountPermissionsSheet.swift
//  dsmaccess
//
//  Which accounts reach a shared folder, and with which right.
//

import SwiftUI

struct ShareAccountPermissionsSheet: View {
    @State private var viewModel: ShareAccountPermissionsViewModel
    @AccessibilityFocusState private var contentFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let onFinish: (DSMOperationOutcome) -> Void

    init(
        shareName: String,
        session: SessionStore,
        onFinish: @escaping (DSMOperationOutcome) -> Void
    ) {
        _viewModel = State(
            initialValue: ShareAccountPermissionsViewModel(shareName: shareName, session: session)
        )
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "share_permissions.accounts.title", defaultValue: "Access to \(viewModel.shareName)"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Picker("share_permissions.accounts.kind.label", selection: $viewModel.kind) {
                ForEach(DSMPermissionHolder.Kind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("share_permissions.accounts.kind.hint")

            content

            HStack {
                if viewModel.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("share_permissions.save.progress")
                }
                Spacer()
                if viewModel.hasChanges {
                    Button("common.button.cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
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
                }
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 460)
        .task {
            await viewModel.load()
            contentFocused = true
            VoiceOver.announce(
                viewModel.summary,
                category: viewModel.errorMessage == nil ? .result : .error
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.permissions.isEmpty {
            ModuleLoadingView("share_permissions.accounts.loading")
                .accessibilityFocused($contentFocused)
        } else if let error = viewModel.errorMessage {
            ModuleErrorView(message: error) {
                Task { await viewModel.load() }
            }
            .accessibilityFocused($contentFocused)
        } else if viewModel.permissions.isEmpty {
            EmptyModuleView(
                title: "share_permissions.accounts.empty",
                systemImage: "person.2.slash",
                description: "share_permissions.accounts.empty.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            SharePermissionTableView(
                permissions: viewModel.permissions,
                subject: .accounts,
                isEnabled: !viewModel.isSaving
            ) { account, level in
                viewModel.setLevel(level, for: account)
            }
            .accessibilityFocused($contentFocused)
        }
    }
}
