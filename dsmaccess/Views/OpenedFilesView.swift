//
//  OpenedFilesView.swift
//  dsmaccess
//
//  Onglet « Fichiers ouverts » du moniteur de ressources, en tableau triable comme les
//  autres onglets du module.
//
//  Lecture seule. DSM sait aussi fermer un fichier ouvert, mais sa méthode `kick` tue le
//  processus qui le tient — ce n'est pas une fermeture propre, et le NAS ne l'autorise que
//  pour une poignée de services. Cette action reste à cadrer séparément.
//

import SwiftUI

struct OpenedFilesView: View {
    @Bindable var vm: OpenedFilesViewModel
    @State private var order = [KeyPathComparator(\OpenedFile.sortableService)]
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await vm.load()
                focusContent = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.files.isEmpty {
            ModuleLoadingView("Chargement des fichiers ouverts…")
                .accessibilityFocused($focusContent)
        } else if let error = vm.errorMessage, vm.files.isEmpty {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else if vm.files.isEmpty {
            // Le cas courant sur un NAS au repos, et non une anomalie : le texte le dit pour
            // qu'un écran vide ne passe pas pour un chargement qui a échoué.
            EmptyModuleView(
                title: "Aucun fichier ouvert",
                systemImage: "doc",
                description: "Le NAS ne tient aucun fichier ouvert en ce moment. Cette liste se remplit quand un service ou une session réseau lit ou écrit un fichier."
            )
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.readableRed)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                Text("Fichiers ouverts")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityFocused($focusContent)

                Table(vm.files.sorted(using: order), sortOrder: $order) {
                    TableColumn("Fichier", value: \.sortableName) { file in
                        Text(file.displayName)
                    }
                    // Le dossier seul, sans répéter le nom du fichier : DSM range les deux
                    // dans `path`, qui se termine par le nom.
                    TableColumn("Dossier", value: \.sortableFolder) { file in
                        Text(vm.folderText(for: file))
                    }
                    TableColumn("Service", value: \.sortableService) { file in
                        Text(vm.serviceText(for: file))
                    }
                    TableColumn("Compte", value: \.sortableAccount) { file in
                        Text(vm.accountText(for: file))
                    }
                    TableColumn("Machine", value: \.sortableHost) { file in
                        Text(vm.hostText(for: file))
                    }
                }

                Text("Un service du NAS lui-même n’a ni compte ni machine d’origine : ces colonnes affichent alors un tiret.")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                if vm.isTruncated {
                    Text("\(vm.files.count) fichiers affichés sur \(vm.totalCount) ouverts.")
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            }
        }
    }
}
