//
//  PackageSourcesSheet.swift
//  dsmaccess
//
//  Gestion accessible des sources tierces du Centre de paquets.
//

import SwiftUI

struct PackageSourcesSheet: View {
    @State private var vm: PackageSourcesViewModel
    @State private var editorRequest: PackageSourceEditorRequest?
    @State private var pendingDeletion: PackageSource?
    @State private var operationTask: Task<Void, Never>?
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusStatus: Bool
    @Environment(\.dismiss) private var dismiss

    init(session: SessionStore) {
        _vm = State(initialValue: PackageSourcesViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 680, height: 480)
        .interactiveDismissDisabled(vm.isSaving || operationTask != nil)
        .task {
            focusHeading = true
            VoiceOver.announce(String(localized: "packages.sources.title"), category: .navigation)
            await load()
        }
        .sheet(item: $editorRequest) { request in
            PackageSourceEditorSheet(vm: vm, source: request.source)
        }
        .confirmationDialog(
            "packages.sources.remove.confirm",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { source in
            Button(String(localized: "common.action.delete_item", defaultValue: "Delete \(source.name)"), role: .destructive) {
                delete(source)
            }
            Button("common.button.cancel", role: .cancel) { }
        } message: { source in
            Text(
                String(localized: "packages.sources.remove.confirm.description", defaultValue: "The “\(source.name)” source will be removed from Package Center. Installed packages will not be stopped or uninstalled.")
            )
        }
        .onDisappear {
            operationTask?.cancel()
        }
    }

    private var header: some View {
        HStack {
            Text("packages.sources.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)
            Spacer()
            if vm.isLoading || vm.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(progressLabel)
            }
        }
        .padding()
    }

    private var progressLabel: String {
        vm.isSaving
            ? String(localized: "packages.sources.saving.progress")
            : String(localized: "packages.sources.loading.label")
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.sources.isEmpty {
            ProgressView("packages.sources.loading.progress")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityFocused($focusStatus)
        } else if let error = vm.errorMessage, vm.sources.isEmpty {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.red)
                Button("common.button.retry") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if vm.sources.isEmpty {
            ContentUnavailableView {
                Label("packages.sources.empty.title", systemImage: "shippingbox")
            } description: {
                Text("packages.sources.empty.description")
            } actions: {
                Button("packages.sources.add.button") {
                    editorRequest = PackageSourceEditorRequest(source: nil)
                }
                .disabled(vm.isSaving)
            }
            .accessibilityFocused($focusStatus)
        } else {
            VStack(spacing: 0) {
                if let error = vm.operationErrorMessage ?? vm.errorMessage {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityFocused($focusStatus)
                        Spacer()
                        Button("common.button.dismiss_error") {
                            vm.operationErrorMessage = nil
                            vm.errorMessage = nil
                        }
                    }
                    .padding()
                }
                List(vm.sources) { source in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.name)
                                .fontWeight(.medium)
                            Text(source.feed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("common.button.edit", systemImage: "pencil") {
                            editorRequest = PackageSourceEditorRequest(source: source)
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(String(localized: "packages.sources.edit.action", defaultValue: "Edit the \(source.name) source"))
                        .disabled(vm.isSaving || operationTask != nil)
                        Button(role: .destructive) {
                            pendingDeletion = source
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(String(localized: "packages.sources.remove.action", defaultValue: "Remove the \(source.name) source"))
                        .disabled(vm.isSaving || operationTask != nil)
                    }
                    .accessibilityElement(children: .contain)
                }
                .accessibilityLabel("packages.sources.table.label")
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("packages.sources.add.button", systemImage: "plus") {
                editorRequest = PackageSourceEditorRequest(source: nil)
            }
            .disabled(vm.isSaving || operationTask != nil)
            .help("packages.sources.add.hint")
            Spacer()
            Button("common.button.close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(vm.isSaving || operationTask != nil)
        }
        .padding()
    }

    private func load() async {
        VoiceOver.announce(
            String(localized: "packages.sources.loading.progress"),
            category: .progress,
            priority: .low
        )
        await vm.load()
        guard !Task.isCancelled else { return }
        if let error = vm.errorMessage {
            focusStatus = true
            VoiceOver.announce(error, category: .error, priority: .high)
        } else {
            VoiceOver.announce(
                String(localized: "packages.sources.count", defaultValue: "\(vm.sources.count) package sources"),
                category: .result
            )
        }
    }

    private func delete(_ source: PackageSource) {
        guard operationTask == nil else { return }
        VoiceOver.announce(
            String(localized: "packages.sources.remove.progress", defaultValue: "Removing the \(source.name) source…"),
            category: .progress,
            priority: .high
        )
        operationTask = Task {
            let outcome = await vm.delete(source)
            if case .failure = outcome { focusStatus = true }
            if case .cancelled = outcome {
                operationTask = nil
                return
            }
            VoiceOver.announce(outcome, priority: .high)
            operationTask = nil
        }
    }
}

private struct PackageSourceEditorRequest: Identifiable {
    let id = UUID()
    let source: PackageSource?
}

private struct PackageSourceEditorSheet: View {
    private enum FocusTarget: Hashable {
        case name
        case feed
        case error
    }

    @Bindable var vm: PackageSourcesViewModel
    let source: PackageSource?

    @State private var name: String
    @State private var feed: String
    @State private var validationMessage: String?
    @State private var saveTask: Task<Void, Never>?
    @AccessibilityFocusState private var focus: FocusTarget?
    @Environment(\.dismiss) private var dismiss

    init(vm: PackageSourcesViewModel, source: PackageSource?) {
        self.vm = vm
        self.source = source
        _name = State(initialValue: source?.name ?? "")
        _feed = State(initialValue: source?.feed ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editorTitle)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Form {
                TextField("common.column.name", text: $name)
                    .accessibilityFocused($focus, equals: .name)
                TextField("packages.sources.url.label", text: $feed)
                    .accessibilityFocused($focus, equals: .feed)
                Text("packages.sources.add.footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.grouped)

            if let message = validationMessage ?? vm.operationErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityFocused($focus, equals: .error)
            }

            if vm.isSaving {
                ProgressView("packages.sources.saving.progress")
            }

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(vm.isSaving)
                Button("common.button.save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.isSaving)
            }
        }
        .padding(24)
        .frame(width: 500)
        .interactiveDismissDisabled(vm.isSaving)
        .onAppear {
            vm.operationErrorMessage = nil
            focus = .name
            VoiceOver.announce(
                editorTitle,
                category: .navigation
            )
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }

    private var editorTitle: String {
        source == nil
            ? String(localized: "packages.sources.add.title")
            : String(localized: "packages.sources.edit.title")
    }

    private func save() {
        guard saveTask == nil else { return }
        guard PackageSourcesViewModel.validatedSource(name: name, feed: feed) != nil else {
            validationMessage = String(
                localized: "common.validation.invalid_package_source"
            )
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            focus = normalizedName.isEmpty ? .name : .feed
            VoiceOver.announce(
                validationMessage ?? "",
                category: .error,
                priority: .high
            )
            return
        }
        validationMessage = nil
        VoiceOver.announce(
            String(localized: "packages.sources.saving.progress"),
            category: .progress,
            priority: .high
        )
        saveTask = Task {
            let outcome = await vm.save(
                name: name,
                feed: feed,
                originalFeed: source?.feed
            )
            if case .success = outcome {
                VoiceOver.announce(outcome, priority: .high)
                dismiss()
            } else if case .failure = outcome {
                focus = .error
                VoiceOver.announce(outcome, priority: .high)
            }
            saveTask = nil
        }
    }
}
