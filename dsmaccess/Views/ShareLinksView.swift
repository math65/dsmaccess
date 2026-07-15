//
//  ShareLinksView.swift
//  dsmaccess
//
//  Feuille de gestion des liens de partage existants : liste (SYNO.FileStation.Sharing list),
//  copie d'une URL et révocation (delete). Ici une List SwiftUI convient : c'est une liste
//  d'actions (boutons focalisables par VoiceOver), pas une navigation drill-in.
//

import AppKit
import SwiftUI

struct ShareLinksView: View {
    let vm: FileBrowserViewModel
    @AccessibilityFocusState private var focusTitle: Bool
    @AccessibilityFocusState private var focusStatus: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Liens de partage")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusTitle)
                Spacer()
                Button("Fermer", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Fermer les liens de partage")
            }
            content
        }
        .padding(20)
        .frame(width: 480, height: 360)
        .task {
            focusTitle = true
            await loadShareLinks()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingShareLinks && vm.shareLinks.isEmpty {
            ModuleLoadingView("Chargement des liens de partage…")
                .accessibilityFocused($focusStatus)
        } else if let error = vm.shareLinksError {
            VStack(spacing: 12) {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Réessayer") { Task { await loadShareLinks() } }
                    .help("Réessayer de charger les liens de partage")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if vm.shareLinks.isEmpty {
            Text("Aucun lien de partage")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(vm.shareLinks) { link in
                row(for: link)
            }
        }
    }

    private var shareLinksAnnouncement: String {
        if let error = vm.shareLinksError { return error }
        return String(localized: "\(vm.shareLinks.count) liens de partage")
    }

    private func loadShareLinks() async {
        await vm.loadShareLinks()
        guard !Task.isCancelled else { return }
        if vm.shareLinksError == nil {
            focusTitle = true
        } else {
            focusStatus = true
        }
        VoiceOver.announce(
            shareLinksAnnouncement,
            category: vm.shareLinksError == nil ? .result : .error
        )
    }

    private func row(for link: SharingLink) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(link.path ?? link.url)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(link.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                copyToClipboard(link.url)
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .accessibilityLabel("Copier le lien")
            .help("Copier ce lien de partage")
            Button(role: .destructive) {
                Task { let msg = await vm.deleteShareLink(link); VoiceOver.announce(msg, priority: .high) }
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Supprimer")
            .help("Supprimer ce lien de partage")
        }
    }

    private func copyToClipboard(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        VoiceOver.announce(String(localized: "Lien copié"))
    }
}
