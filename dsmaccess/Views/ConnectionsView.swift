//
//  ConnectionsView.swift
//  dsmaccess
//
//  Onglet « Connexions » du moniteur de ressources.
//

import SwiftUI

struct ConnectionsView: View {
    @Bindable var vm: ConnectionsViewModel
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
            Form {
                Section {
                    ForEach(vm.connections) { connection in
                        LabeledContent {
                            Text(vm.detailText(for: connection))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.account ?? String(localized: "Compte inconnu"))
                                if let description = connection.descriptionText,
                                   !description.isEmpty {
                                    Text(description)
                                        .font(.callout)
                                        .foregroundStyle(.readableSecondary)
                                }
                                // Écrit, pas seulement annoncé : reconnaître sa propre
                                // session doit être possible à l'œil comme à l'oreille.
                                if connection.isCurrent {
                                    Text("Session courante")
                                        .font(.callout)
                                        .foregroundStyle(.readableGreen)
                                }
                            }
                        }
                        // Sans cette étiquette, VoiceOver lit deux textes empilés sans
                        // dire lequel est le compte et lequel la ressource.
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(accessibilityLabel(for: connection))
                    }
                } header: {
                    Text("Sessions ouvertes")
                } footer: {
                    Text("Une même machine peut apparaître plusieurs fois : une ligne par protocole.")
                }
            }
            .formStyle(.grouped)
            .labeledContentStyle(.readable)
            .accessibilityFocused($focusContent)
        }
    }

    private func accessibilityLabel(for connection: NASConnection) -> Text {
        let account = connection.account ?? String(localized: "Compte inconnu")
        let detail = vm.detailText(for: connection)
        guard connection.isCurrent else {
            return Text("\(account), \(detail)")
        }
        // Reconnaître sa propre session évite d'agir sur la mauvaise.
        return Text("\(account), \(detail), session courante")
    }
}
