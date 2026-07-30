//
//  SharesView.swift
//  dsmaccess
//  Administration of DSM shared folders.

import AppKit
import SwiftUI

struct SharesView: View {
    @State private var vm: SharesViewModel
    @State private var showCreateSheet = false
    @State private var pendingDelete: SharedFolder?
    @State private var searchText = ""
    @AccessibilityFocusState private var focusContent: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _vm = State(initialValue: SharesViewModel(session: session))
    }

    var body: some View {
        content
        .searchable(text: $searchText, prompt: "shares.search.label")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("shares.refresh.button")
            }

            ToolbarItem {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("shares.create.button", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("shares.create.button")
            }
        }
        .task {
            await load(restoresInitialFocus: true)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateShareSheet(volumes: vm.volumes) { name, volume, description in
                Task {
                    let msg = await vm.create(name: name, volumePath: volume, description: description)
                    VoiceOver.announce(msg, priority: .high)
                }
            }
        }
        .sheet(item: $pendingDelete) { folder in
            DeleteShareSheet(folder: folder) {
                Task {
                    let msg = await vm.delete(folder)
                    VoiceOver.announce(msg, priority: .high)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.shares.isEmpty {
            ModuleLoadingView()
                .accessibilityFocused($focusContent)
        } else if let error = vm.errorMessage {
            ModuleErrorView(message: error) {
                Task { await load() }
            }
            .accessibilityFocused($focusContent)
        } else if vm.shares.isEmpty {
            EmptyModuleView(
                title: "common.empty.shared_folders",
                systemImage: "externaldrive.badge.person.crop",
                description: "shares.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else if filteredShares.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(filteredShares) { share in
                row(for: share)
            }
            .accessibilityLabel("common.module.shared_folders")
            .accessibilityFocused($focusContent)
        }
    }

    private func row(for share: SharedFolder) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(share.displayName).fontWeight(.medium)
                if let sub = share.subtitleText {
                    Text(sub).font(.caption).foregroundStyle(.readableSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(share.accessibilityLabel)
            // The combined element has no role by default; without this trait,
            // VoiceOver and the audit see it as an element of unknown nature.
            .accessibilityAddTraits(.isStaticText)
            Spacer()
            Button(role: .destructive) {
                pendingDelete = share
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel(String(localized: "common.action.delete_item", defaultValue: "Delete \(share.displayName)"))
            .help(String(localized: "common.action.delete_item", defaultValue: "Delete \(share.displayName)"))
        }
        .contextMenu {
            if session.connectionTarget?.directEndpoint != nil {
                Button("shares.smb_path.copy.button") { copySMBPath(for: share) }
                    .help("shares.smb_path.copy.label")
                Divider()
            }
            Button("common.menu.delete", role: .destructive) { pendingDelete = share }
                .help("shares.row.delete.button")
        }
    }

    private var filteredShares: [SharedFolder] {
        guard !searchText.isEmpty else { return vm.shares }
        return vm.shares.filter {
            $0.displayName.localizedStandardContains(searchText)
                || ($0.desc?.localizedStandardContains(searchText) == true)
                || ($0.volumeText?.localizedStandardContains(searchText) == true)
        }
    }

    private func copySMBPath(for share: SharedFolder) {
        guard let host = session.connectionTarget?.directEndpoint?.host else { return }
        let path = "smb://\(host)/\(share.displayName)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        VoiceOver.announce(String(localized: "shares.smb_path.copied"))
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "shares.loading"),
            category: .progress,
            priority: .low
        )
        await vm.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        }
        VoiceOver.announce(
            vm.summary,
            category: vm.errorMessage == nil ? .result : .error
        )
    }
}

private struct CreateShareSheet: View {
    let volumes: [String]
    let onConfirm: (_ name: String, _ volumePath: String, _ description: String) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var volume: String
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var a11yFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(volumes: [String],
         onConfirm: @escaping (String, String, String) -> Void) {
        self.volumes = volumes
        self.onConfirm = onConfirm
        _volume = State(initialValue: volumes.first ?? "/volume1")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("shares.create.button")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LabeledField(label: "shares.name.column") {
                TextField("shares.name.column", text: $name)
                    .focused($nameFocused)
                    .accessibilityFocused($a11yFocused)
                    .onSubmit(confirm)
                    .help("shares.create.name.label")
            }

            if volumes.count > 1 {
                LabeledField(label: "common.column.volume") {
                    Picker("common.column.volume", selection: $volume) {
                        ForEach(volumes, id: \.self) { v in
                            Text(volumeLabel(for: v)).tag(v)
                        }
                    }
                    .labelsHidden()
                    .help("shares.create.volume.label")
                }
            }

            LabeledField(label: "common.field.description_optional") {
                TextField("common.field.description_optional", text: $description)
                    .help("shares.create.description.label")
            }

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("shares.create.cancel.button")
                Button("common.button.create", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
                    .help("shares.create.confirm.button")
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            nameFocused = true
            a11yFocused = true
            VoiceOver.announce(
                String(localized: "shares.create.button"),
                category: .navigation
            )
        }
    }

    private func confirm() {
        let value = trimmedName
        guard !value.isEmpty else { return }
        onConfirm(value, volume, description.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

private struct DeleteShareSheet: View {
    let folder: SharedFolder
    let onConfirm: () -> Void

    @State private var typedName = ""
    @FocusState private var fieldFocused: Bool
    @AccessibilityFocusState private var a11yFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var nameMatches: Bool {
        typedName.trimmingCharacters(in: .whitespacesAndNewlines) == folder.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("shares.delete.confirm.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(String(localized: "shares.delete.confirm.message", defaultValue: "“\(folder.displayName)” and all its contents will be permanently deleted. This action cannot be undone."))
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "shares.delete.confirm.name_field.placeholder") {
                TextField(folder.displayName, text: $typedName)
                    .focused($fieldFocused)
                    .accessibilityFocused($a11yFocused)
                    .help("shares.delete.confirm.name_field.label")
            }

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("shares.delete.cancel.button")
                Button("shares.delete.confirm.button", role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .disabled(!nameMatches)
                .help("shares.delete.confirm.button.label")
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            fieldFocused = true
            a11yFocused = true
            VoiceOver.announce(
                String(localized: "shares.delete.confirm.instruction"),
                category: .navigation
            )
        }
    }
}
