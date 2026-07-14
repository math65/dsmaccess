//
//  SharesView.swift
//  dsmaccess
//
//  Module « Partages » : liste les dossiers partagés du NAS, permet d'en créer et d'en
//  supprimer (SYNO.Core.Share). Liste plate d'actions → List SwiftUI (comme ShareLinksView),
//  pas de navigation drill-in. La suppression exige de retaper le nom (destruction totale).
//

import SwiftUI

struct SharesView: View {
    @State private var vm: SharesViewModel
    @State private var showCreateSheet = false
    @State private var pendingDelete: SharedFolder?
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: SharesViewModel(session: session))
    }

    var body: some View {
        content
        .navigationTitle("Dossiers partagés")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await load() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser les dossiers partagés")

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
            await load()
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
        } else {
            List(vm.shares) { share in
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
            Spacer()
            Button(role: .destructive) {
                pendingDelete = share
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Supprimer")
        }
        .contextMenu {
            Button("Supprimer…", role: .destructive) { pendingDelete = share }
        }
    }

    private func load() async {
        focusContent = true
        await vm.load()
        guard !Task.isCancelled else { return }
        focusContent = true
        VoiceOver.announce(vm.summary)
    }
}

/// Feuille de création d'un dossier partagé : nom, volume (si plusieurs), description.
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
            }

            if volumes.count > 1 {
                LabeledField(label: "Volume") {
                    Picker("Volume", selection: $volume) {
                        ForEach(volumes, id: \.self) { v in
                            Text(volumeLabel(for: v)).tag(v)
                        }
                    }
                    .labelsHidden()
                }
            }

            LabeledField(label: "Description (facultative)") {
                TextField("Description (facultative)", text: $description)
            }

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Créer", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            nameFocused = true
            a11yFocused = true
            VoiceOver.announce(String(localized: "Créer un dossier partagé"))
        }
    }

    private func confirm() {
        let value = trimmedName
        guard !value.isEmpty else { return }
        onConfirm(value, volume, description.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

/// Confirmation FORTE de suppression : il faut retaper le nom exact (la suppression
/// efface tout le contenu du partage — irréversible).
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
            }

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Supprimer définitivement", role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .disabled(!nameMatches)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            fieldFocused = true
            a11yFocused = true
            VoiceOver.announce(String(localized: "Confirmez la suppression en retapant le nom du dossier partagé."))
        }
    }
}
