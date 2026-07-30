//
//  ConnectionsView.swift
//  dsmaccess
//
//  Onglet « Connexions » du moniteur de ressources, en tableau triable : chaque valeur
//  reste dans sa colonne, et les en-têtes trient d'un clic comme partout sur le Mac.
//  La coupure d'une session est confirmée avant d'être envoyée, et son résultat annoncé.
//

import SwiftUI

struct ConnectionsView: View {
    @Bindable var vm: ConnectionsViewModel
    @State private var order = [KeyPathComparator(\NASConnection.sortableDate, order: .reverse)]
    @State private var selection: Set<String> = []
    @State private var pendingKick: [NASConnection] = []
    @AccessibilityFocusState private var focusContent: Bool


    var body: some View {
        content
            .task {
                await vm.load()
                focusContent = true
            }
            .confirmationDialog(
                kickTitle,
                isPresented: Binding(
                    get: { !pendingKick.isEmpty },
                    set: { if !$0 { pendingKick = [] } }
                )
            ) {
                Button(kickConfirmationLabel, role: .destructive) {
                    let targets = pendingKick
                    pendingKick = []
                    Task { await kick(targets) }
                }
                Button("Annuler", role: .cancel) { }
                    .help("Laisser ces sessions ouvertes")
            } message: {
                Text(kickMessage)
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

                Table(
                    vm.connections.sorted(using: order),
                    selection: $selection,
                    sortOrder: $order
                ) {
                    TableColumn("Compte", value: \.sortableAccount) { connection in
                        Text(vm.accountText(for: connection))
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
                    // Trois valeurs que DSM n'affiche pas. « Client » et « Lieu » restent vides
                    // sur un accès local — le NAS ne les renseigne que pour certaines sessions —
                    // d'où le tiret, cohérent avec les autres colonnes de ce module.
                    TableColumn("Client", value: \.sortableUserAgent) { connection in
                        Text(vm.clientText(for: connection))
                    }
                    TableColumn("Lieu", value: \.sortableLocation) { connection in
                        Text(vm.locationText(for: connection))
                    }
                    TableColumn("Deux étapes", value: \.sortableTwoFactor) { connection in
                        Text(vm.twoFactorText(for: connection))
                    }
                    // Pas de colonne « session courante » : vérifié sur DSM 7.4, le NAS ne
                    // lève `is_current_connected` que pour son client web. Interrogé par
                    // l'app, il ne marque aucune ligne — la colonne n'aurait que des tirets.
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    let targets = connections(for: ids)
                    if targets.contains(where: vm.canKick) {
                        Button("Couper la session…", role: .destructive) {
                            pendingKick = targets.filter(vm.canKick)
                        }
                    }
                }

                actionBar

                Text("Une même machine peut apparaître plusieurs fois : une ligne par protocole.")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
                    .padding(12)
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button(kickButtonLabel) {
                pendingKick = selectedConnections.filter(vm.canKick)
            }
            .disabled(!selectedConnections.contains(where: vm.canKick))
            .help("Fermer les sessions sélectionnées sur le NAS")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private var selectedConnections: [NASConnection] {
        connections(for: selection)
    }

    private func connections(for ids: Set<String>) -> [NASConnection] {
        vm.connections.filter { ids.contains($0.id) }
    }

    /// Le libellé porte le nombre : sans lui, le bouton s'annonce « Couper » sans dire sur
    /// quoi il porte, et rien ne distingue une session de six.
    private var kickButtonLabel: LocalizedStringKey {
        let count = selectedConnections.filter(vm.canKick).count
        return count <= 1 ? "Couper la session sélectionnée…" : "Couper les \(count) sessions sélectionnées…"
    }

    private var kickTitle: LocalizedStringKey {
        pendingKick.count <= 1 ? "Couper cette session ?" : "Couper ces \(pendingKick.count) sessions ?"
    }

    private var kickConfirmationLabel: LocalizedStringKey {
        guard let only = pendingKick.first, pendingKick.count == 1 else {
            return "Couper les \(pendingKick.count) sessions"
        }
        return "Couper la session de \(vm.accountText(for: only))"
    }

    /// La confirmation nomme les sessions visées et dit ce qui se passe : un transfert en
    /// cours sur ces sessions est interrompu. L'avertissement sur sa propre session n'est pas
    /// une certitude — le NAS ne dit pas laquelle est celle de l'app — et le dit ainsi.
    private var kickMessage: String {
        var sentences: [String] = []
        if let only = pendingKick.first, pendingKick.count == 1 {
            sentences.append(
                String(
                    localized: "La session de \(vm.accountText(for: only)) ouverte depuis \(only.address ?? String(localized: "une adresse inconnue")) sera fermée, et tout transfert en cours sur cette session interrompu."
                )
            )
        } else {
            let accounts = pendingKick.map { vm.accountText(for: $0) }
            sentences.append(
                String(
                    localized: "Ces sessions seront fermées et tout transfert en cours interrompu. Comptes concernés : \(accounts.formatted(.list(type: .and)))."
                )
            )
        }
        if vm.mayCloseOwnSession(pendingKick) {
            // Deux phrases complètes plutôt qu'une tournure qui vaudrait pour les deux cas :
            // « l'une de ces sessions » devant une seule ligne sélectionnée s'entend comme une
            // erreur, et un accord bricolé se traduirait mal.
            sentences.append(
                pendingKick.count == 1
                    ? String(
                        localized: "Cette session peut être celle de cette app : vous seriez alors déconnecté du NAS."
                    )
                    : String(
                        localized: "L’une de ces sessions peut être celle de cette app : vous seriez alors déconnecté du NAS."
                    )
            )
        }
        return sentences.joined(separator: " ")
    }

    private func kick(_ targets: [NASConnection]) async {
        let outcome = await vm.kick(targets)
        // La liste a été rechargée : les identifiants retenus ne désignent plus rien, et une
        // sélection fantôme réarmerait le bouton sur des sessions disparues.
        selection = []
        switch outcome {
        case .success(let message):
            VoiceOver.announce(message, category: .result, priority: .high)
            focusContent = true
        case .failure(let message):
            VoiceOver.announce(message, category: .error, priority: .high)
        case .cancelled:
            break
        }
    }
}
