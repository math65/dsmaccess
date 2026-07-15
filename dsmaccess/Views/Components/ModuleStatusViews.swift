//
//  ModuleStatusViews.swift
//  dsmaccess
//
//  États standardisés des modules : chargement, erreur et contenu vide.
//

import SwiftUI

struct ModuleLoadingView: View {
    let message: LocalizedStringKey

    init(_ message: LocalizedStringKey = "Chargement…") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ModuleErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Impossible de charger les données", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Réessayer", action: retry)
                .help("Réessayer le chargement")
        }
    }
}

struct EmptyModuleView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        }
    }
}
