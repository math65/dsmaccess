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
    @State private var shareItem: FileStationItem?
    @State private var showingShareLinks = false

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
        .sheet(item: $shareItem) { item in
            ShareSheet(item: item) { password, dateExpired in
                await vm.createShareLink(for: item, password: password, dateExpired: dateExpired)
            }
        }
        .sheet(isPresented: $showingShareLinks) {
            ShareLinksView(vm: vm)
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

            Button {
                startUpload()
            } label: {
                Label("Envoyer", systemImage: "square.and.arrow.up")
            }
            .disabled(!vm.canWrite)
            .keyboardShortcut("u", modifiers: .command)
            .accessibilityHint("Envoie des fichiers depuis votre Mac vers ce dossier")

            Button {
                VoiceOver.announce(String(localized: "Collage en cours…"), priority: .low)
                Task { let msg = await vm.paste(); VoiceOver.announce(msg, priority: .high) }
            } label: {
                Label("Coller", systemImage: "doc.on.clipboard")
            }
            .disabled(!vm.canPaste)
            .keyboardShortcut("v", modifiers: .command)
            .accessibilityHint("Colle l'élément copié ou coupé dans ce dossier")

            Button {
                showingShareLinks = true
            } label: {
                Label("Liens de partage", systemImage: "link")
            }
            .accessibilityHint("Gère les liens de partage existants")
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
                onCopy: { item in VoiceOver.announce(vm.copy(item)) },
                onCut: { item in VoiceOver.announce(vm.cut(item)) },
                onShare: { item in shareItem = item },
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

    /// Choisit un ou plusieurs fichiers via un panneau d'ouverture, puis lance l'envoi.
    private func startUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        VoiceOver.announce(String(localized: "Envoi en cours…"), priority: .low)
        Task {
            let message = await vm.upload(fileURLs: urls)
            VoiceOver.announce(message, priority: .high)
        }
    }
}
