//
//  SharesView.swift
//  dsmaccess
//  Administration des dossiers partagés DSM.

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
        .searchable(text: $searchText, prompt: "Rechercher des dossiers partagés")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser les dossiers partagés")
            }

            ToolbarItem {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Créer un dossier partagé", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Créer un dossier partagé")
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
                title: "Aucun dossier partagé",
                systemImage: "externaldrive.badge.person.crop",
                description: "Créez un dossier partagé pour le rendre disponible sur le réseau."
            )
            .accessibilityFocused($focusContent)
        } else if filteredShares.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(filteredShares) { share in
                row(for: share)
            }
            .accessibilityFocused($focusContent)
        }
    }

    private func row(for share: SharedFolder) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(share.displayName).fontWeight(.medium)
                if let sub = share.subtitleText {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(share.accessibilityLabel)
            Spacer()
            Button(role: .destructive) {
                pendingDelete = share
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Supprimer \(share.displayName)")
            .help(String(localized: "Supprimer \(share.displayName)"))
        }
        .contextMenu {
            Button("Copier le chemin SMB") { copySMBPath(for: share) }
                .help("Copier le chemin SMB de ce dossier partagé")
            Divider()
            Button("Supprimer…", role: .destructive) { pendingDelete = share }
                .help("Supprimer ce dossier partagé")
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
        guard let host = session.endpoint?.host else { return }
        let path = "smb://\(host)/\(share.displayName)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        VoiceOver.announce(String(localized: "Chemin SMB copié"))
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "Chargement des dossiers partagés…"),
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
            Text("Créer un dossier partagé")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LabeledField(label: "Nom du dossier partagé") {
                TextField("Nom du dossier partagé", text: $name)
                    .focused($nameFocused)
                    .accessibilityFocused($a11yFocused)
                    .onSubmit(confirm)
                    .help("Nom du nouveau dossier partagé")
            }

            if volumes.count > 1 {
                LabeledField(label: "Volume") {
                    Picker("Volume", selection: $volume) {
                        ForEach(volumes, id: \.self) { v in
                            Text(volumeLabel(for: v)).tag(v)
                        }
                    }
                    .labelsHidden()
                    .help("Choisir le volume du nouveau dossier partagé")
                }
            }

            LabeledField(label: "Description (facultative)") {
                TextField("Description (facultative)", text: $description)
                    .help("Description facultative du dossier partagé")
            }

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Annuler la création du dossier partagé")
                Button("Créer", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
                    .help("Créer le dossier partagé")
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            nameFocused = true
            a11yFocused = true
            VoiceOver.announce(
                String(localized: "Créer un dossier partagé"),
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
            Text("Supprimer ce dossier partagé ?")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("« \(folder.displayName) » et tout son contenu seront supprimés définitivement. Cette action est irréversible.")
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "Retapez le nom du dossier pour confirmer") {
                TextField(folder.displayName, text: $typedName)
                    .focused($fieldFocused)
                    .accessibilityFocused($a11yFocused)
                    .help("Retaper le nom du dossier partagé pour confirmer")
            }

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Annuler la suppression du dossier partagé")
                Button("Supprimer définitivement", role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .disabled(!nameMatches)
                .help("Supprimer définitivement le dossier partagé")
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            fieldFocused = true
            a11yFocused = true
            VoiceOver.announce(
                String(localized: "Confirmez la suppression en retapant le nom du dossier partagé."),
                category: .navigation
            )
        }
    }
}
