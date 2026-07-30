//
//  LogsSecurityView.swift
//  dsmaccess
//
//  Journal système du NAS et liste de blocage du blocage automatique, en tableaux triables.
//
//  Deux onglets et non deux sections empilées : le journal se parcourt, la liste de blocage
//  s'agit dessus, et mêler les deux obligeait à traverser l'un pour atteindre l'autre.
//

import SwiftUI

struct LogsSecurityView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case logs
        case blockList

        var id: Self { self }
    }

    @State private var vm: LogsSecurityViewModel
    @State private var pane = Pane.logs
    @State private var logOrder = [
        KeyPathComparator(\SystemLogEntry.sortableDate, order: .reverse)
    ]
    @State private var blockOrder = [
        KeyPathComparator(\BlockedAddress.sortableBlockedAt, order: .reverse)
    ]
    @State private var blockSelection: Set<BlockedAddress.ID> = []
    @State private var pendingUnblock: [BlockedAddress] = []
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: LogsSecurityViewModel(session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $pane) {
                logsPane
                    .tabItem { Text("Journal") }
                    .tag(Pane.logs)
                blockListPane
                    .tabItem { Text("Liste de blocage") }
                    .tag(Pane.blockList)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await vm.load(announce: true)
                    }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser le journal et la liste de blocage")
            }
        }
        .task {
            await vm.load()
            focusContent = true
        }
        .confirmationDialog(
            unblockTitle,
            isPresented: Binding(
                get: { !pendingUnblock.isEmpty },
                set: { if !$0 { pendingUnblock = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Débloquer", role: .destructive) {
                let addresses = pendingUnblock
                pendingUnblock = []
                Task {
                    let outcome = await vm.unblock(addresses)
                    VoiceOver.announce(outcome, priority: .high)
                }
            }
            Button("Annuler", role: .cancel) { pendingUnblock = [] }
        } message: {
            Text("Le NAS acceptera de nouveau les connexions venant de ces adresses. Le blocage automatique peut les bloquer à nouveau si les échecs de connexion reprennent.")
        }
    }

    private var unblockTitle: String {
        if pendingUnblock.count == 1, let only = pendingUnblock.first {
            return String(localized: "Débloquer l’adresse \(only.address) ?")
        }
        return String(localized: "Débloquer \(pendingUnblock.count) adresses ?")
    }

    // MARK: - Journal

    @ViewBuilder
    private var logsPane: some View {
        if vm.isLoading && vm.logs.isEmpty {
            ModuleLoadingView("Chargement du journal…")
                .accessibilityFocused($focusContent)
        } else if let error = vm.errorMessage, vm.logs.isEmpty {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.readableRed)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                Text("Journal système")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityFocused($focusContent)

                logFilters

                if vm.visibleLogs.isEmpty {
                    EmptyModuleView(
                        title: "Aucune entrée",
                        systemImage: "doc.text.magnifyingglass",
                        description: vm.logs.isEmpty
                            ? "Le NAS n’a consigné aucune entrée correspondant à cette recherche."
                            : "Aucune entrée de ce niveau parmi celles chargées. Choisissez un autre niveau."
                    )
                } else {
                    logTable
                }

                HStack(spacing: 12) {
                    Text(vm.summary)
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)

                    if vm.canLoadMore {
                        Button("Charger les entrées plus anciennes") {
                            Task {
                                if let outcome = await vm.loadMore() {
                                    VoiceOver.announce(outcome, priority: .high)
                                }
                            }
                        }
                        .disabled(vm.isLoadingMore)
                        .accessibilityHint("Ajoute les entrées suivantes à la suite de celles déjà affichées")
                        .help("Ajouter la tranche suivante du journal")
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private var logFilters: some View {
        HStack(spacing: 12) {
            // La recherche part au NAS, qui filtre le journal entier et non la seule page
            // chargée : chercher dans 6995 entrées ne se fait pas côté app.
            TextField("Rechercher dans le journal", text: $vm.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .accessibilityHint("Le NAS cherche dans tout le journal, pas seulement dans les entrées affichées")

            Picker("Niveau", selection: $vm.levelFilter) {
                ForEach(LogsSecurityViewModel.LevelFilter.allCases) { filter in
                    Text(vm.filterText(filter)).tag(filter)
                }
            }
            .frame(maxWidth: 220)
            .help("N’afficher que les entrées de ce niveau")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var logTable: some View {
        Table(vm.visibleLogs.sorted(using: logOrder), sortOrder: $logOrder) {
            TableColumn("Heure", value: \.sortableDate) { entry in
                Text(vm.dateText(for: entry))
            }
            // Triée par gravité et non par ordre alphabétique : « Erreur » doit se ranger
            // après « Avertissement ».
            TableColumn("Niveau", value: \.sortableLevel) { entry in
                Text(vm.levelText(entry.level))
                    .foregroundStyle(color(for: entry.level))
            }
            TableColumn("Catégorie") { entry in
                Text(vm.categoryText(for: entry))
            }
            TableColumn("Compte", value: \.sortableAccount) { entry in
                Text(vm.accountText(for: entry))
            }
            TableColumn("Événement", value: \.sortableMessage) { entry in
                Text(entry.message)
            }
        }
    }

    // MARK: - Liste de blocage

    @ViewBuilder
    private var blockListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Liste de blocage")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if let error = vm.blockedAddressesError {
                // Un compte sans privilège d'administration se voit refuser cette liste : le
                // dire, plutôt que de présenter une liste vide qui se lirait comme un NAS sans
                // adresse bloquée.
                ModuleErrorView(message: error) {
                    Task { await vm.load(announce: true) }
                }
            } else if vm.blockedAddresses.isEmpty {
                EmptyModuleView(
                    title: "Aucune adresse bloquée",
                    systemImage: "hand.raised",
                    description: "Le blocage automatique n’a bloqué aucune adresse, et aucune n’a été ajoutée à la main. Une adresse y entre après trop d’échecs de connexion."
                )
            } else {
                Table(
                    vm.blockedAddresses.sorted(using: blockOrder),
                    selection: $blockSelection,
                    sortOrder: $blockOrder
                ) {
                    TableColumn("Adresse", value: \.address) { address in
                        Text(address.address)
                    }
                    TableColumn("Bloquée le", value: \.sortableBlockedAt) { address in
                        Text(vm.blockedAtText(for: address))
                    }
                    TableColumn("Expiration", value: \.sortableExpiry) { address in
                        Text(vm.expiryText(for: address))
                    }
                    TableColumn("Lieu", value: \.sortableCountry) { address in
                        Text(vm.countryText(for: address))
                    }
                }

                HStack {
                    Button("Débloquer", role: .destructive) {
                        pendingUnblock = selectedAddresses
                    }
                    .disabled(selectedAddresses.isEmpty || !selectedAddresses.allSatisfy(vm.canUnblock))
                    .help("Retirer les adresses sélectionnées de la liste de blocage")

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private var selectedAddresses: [BlockedAddress] {
        vm.blockedAddresses.filter { blockSelection.contains($0.id) }
    }

    /// La couleur double le mot, elle ne le remplace pas : le niveau est toujours écrit.
    private func color(for level: SystemLogEntry.Level) -> Color {
        switch level {
        case .error: .readableRed
        case .warning: .readableOrange
        case .info, .other: .primary
        }
    }
}
