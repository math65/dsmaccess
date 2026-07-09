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
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                Task { await vm.goUp(); announce() }
            } label: {
                Label("Dossier parent", systemImage: "chevron.up")
            }
            .disabled(!vm.canGoUp)
            .accessibilityHint("Remonte au dossier parent")

            Text(vm.breadcrumb)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.head)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeader)

            Spacer()
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
                onActivate: { item in
                    if item.isdir {
                        Task { await vm.open(item); announce() }
                    } else {
                        startDownload(item)
                    }
                },
                onDownload: { item in startDownload(item) },
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
