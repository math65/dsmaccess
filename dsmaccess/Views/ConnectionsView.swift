//
//  ConnectionsView.swift
//  dsmaccess
//
//  Onglet « Connexions » du moniteur de ressources, en tableau triable : chaque valeur
//  reste dans sa colonne, et les en-têtes trient d'un clic comme partout sur le Mac.
//

import SwiftUI

struct ConnectionsView: View {
    @Bindable var vm: ConnectionsViewModel
    @State private var order = [KeyPathComparator(\NASConnection.sortableDate, order: .reverse)]
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
        if vm.isLoading && vm.connections.isEmpty {
            ModuleLoadingView("Chargement des connexions…")
        } else if let error = vm.errorMessage, vm.connections.isEmpty {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
        } else if vm.connections.isEmpty {
            ContentUnavailableView(
                "Aucune connexion",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Le NAS ne signale aucune session ouverte.")
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sessions ouvertes")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityFocused($focusContent)

                Table(vm.connections.sorted(using: order), sortOrder: $order) {
                    TableColumn("Compte", value: \.sortableAccount) { connection in
                        Text(connection.account ?? String(localized: "Compte inconnu"))
                    }
                    TableColumn("Protocole", value: \.sortableType) { connection in
                        Text(connection.type ?? String(localized: "Protocole inconnu"))
                    }
                    TableColumn("Adresse", value: \.sortableAddress) { connection in
                        Text(connection.address ?? String(localized: "adresse inconnue"))
                    }
                    TableColumn("Ressource", value: \.sortableDescription) { connection in
                        Text(connection.descriptionText ?? "—")
                    }
                    TableColumn("Ouverte le", value: \.sortableDate) { connection in
                        Text(vm.openedAtText(for: connection))
                    }
                    // Pas de colonne « session courante » : vérifié sur DSM 7.4, le NAS ne
                    // lève `is_current_connected` que pour son client web. Interrogé par
                    // l'app, il ne marque aucune ligne — la colonne n'aurait que des tirets.
                }

                Text("Une même machine peut apparaître plusieurs fois : une ligne par protocole.")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
                    .padding(12)
            }
        }
    }
}
