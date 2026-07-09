//
//  FileBrowserView.swift
//  dsmaccess
//
//  Coquille SwiftUI du module « Fichiers » : en-tête (bouton Remonter + fil d'Ariane) et
//  états chargement / erreur / vide. La liste elle-même est un NSTableView AppKit
//  (voir FileTableView) pour une navigation clavier et VoiceOver dignes du Finder.
//

import AppKit
import SwiftUI

struct FileBrowserView: View {
    @State private var vm: FileBrowserViewModel
    @AccessibilityFocusState private var focusHeader: Bool
    @State private var activeSheet: WriteSheet?
    @State private var pendingDelete: FileStationItem?

    /// Feuille de saisie active (créer un dossier ou renommer un élément).
    private enum WriteSheet: Identifiable {
        case createFolder
        case rename(FileStationItem)
        var id: String {
            switch self {
            case .createFolder: return "createFolder"
            case .rename(let item): return "rename-\(item.id)"
            }
        }
    }

    init(session: SessionStore) {
        _vm = State(initialValue: FileBrowserViewModel(session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            content
        }
        .task {
            focusHeader = true
            await vm.loadCurrent()
            announce()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .createFolder:
                NameEntrySheet(
                    title: "Créer un dossier",
                    fieldLabel: "Nom du dossier",
                    confirmLabel: "Créer",
                    announcement: String(localized: "Créer un dossier")
                ) { name in
                    Task { let msg = await vm.createFolder(named: name); VoiceOver.announce(msg, priority: .high) }
                }
            case .rename(let item):
                NameEntrySheet(
                    title: "Renommer",
                    fieldLabel: "Nouveau nom",
                    confirmLabel: "Renommer",
                    announcement: String(localized: "Renommer « \(item.name) »"),
                    initialName: item.name
                ) { name in
                    Task { let msg = await vm.rename(item, to: name); VoiceOver.announce(msg, priority: .high) }
                }
            }
        }
        .alert("Supprimer cet élément ?",
               isPresented: Binding(get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } }),
               presenting: pendingDelete) { item in
            Button("Supprimer", role: .destructive) {
                Task { let msg = await vm.delete(item); VoiceOver.announce(msg, priority: .high) }
            }
            Button("Annuler", role: .cancel) { }
        } message: { item in
            Text("« \(item.name) » sera supprimé définitivement. Cette action est irréversible.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                Task { await vm.goUp(); announce() }
            } label: {
                Label("Dossier parent", systemImage: "chevron.up")
            }
            .disabled(!vm.canGoUp)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .accessibilityHint("Remonte au dossier parent")

            Text(vm.breadcrumb)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.head)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeader)

            Spacer()

            Button {
                activeSheet = .createFolder
            } label: {
                Label("Créer un dossier", systemImage: "folder.badge.plus")
            }
            .disabled(!vm.canWrite)
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityHint("Crée un dossier dans le dossier courant")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.items.isEmpty {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Chargement…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Réessayer") {
                    Task { await vm.loadCurrent(); announce() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if vm.items.isEmpty {
            Text("Dossier vide")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            FileTableView(
                items: vm.items,
                canWrite: vm.canWrite,
                onActivate: { item in
                    if item.isdir {
                        Task { await vm.open(item); announce() }
                    } else {
                        startDownload(item)
                    }
                },
                onDownload: { item in startDownload(item) },
                onRename: { item in activeSheet = .rename(item) },
                onDelete: { item in pendingDelete = item },
                onGoUp: { Task { await vm.goUp(); announce() } }
            )
        }
    }

    private func announce() {
        VoiceOver.announce(vm.summary)
    }

    /// Choisit une destination via un panneau d'enregistrement, puis lance le téléchargement.
    private func startDownload(_ item: FileStationItem) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = vm.suggestedFilename(for: item)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        VoiceOver.announce(String(localized: "Téléchargement en cours…"), priority: .low)
        Task {
            let message = await vm.downloadItem(item, to: url)
            VoiceOver.announce(message, priority: .high)
        }
    }
}
