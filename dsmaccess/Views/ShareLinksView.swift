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
            }
            content
        }
        .padding(20)
        .frame(width: 480, height: 360)
        .task {
            focusTitle = true
            await vm.loadShareLinks()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingShareLinks && vm.shareLinks.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.shareLinksError {
            VStack(spacing: 12) {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Réessayer") { Task { await vm.loadShareLinks() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button(role: .destructive) {
                Task { let msg = await vm.deleteShareLink(link); VoiceOver.announce(msg, priority: .high) }
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Supprimer")
        }
    }

    private func copyToClipboard(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        VoiceOver.announce(String(localized: "Lien copié"))
    }
}
