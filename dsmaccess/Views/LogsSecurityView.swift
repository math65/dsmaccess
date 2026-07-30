//
//  LogsSecurityView.swift
//  dsmaccess
//
//  Journal système du NAS et liste de blocage du blocage automatique, en tableaux triables.
//
//  Deux onglets et non deux sections empilées : le journal se parcourt, la liste de blocage
//  s'agit dessus, et mêler les deux obligeait à traverser l'un pour atteindre l'autre.
//

import AppKit
import SwiftUI

struct LogsSecurityView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case logs
        case loginActivity
        case blockList
        case settings

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
    @State private var activityOrder = [
        KeyPathComparator(\LoginActivityEvent.sortableDate, order: .reverse)
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
                    // Le champ va dans la barre d'outils, comme dans tous les autres modules.
                    // Il n'est posé que sur cet onglet : la recherche part au NAS, qui filtre
                    // le journal entier, et n'a rien à faire pour une liste de blocage de
                    // quelques lignes.
                    .searchable(text: $vm.searchText, prompt: "Rechercher dans le journal")
                    .tabItem { Text("Journal") }
                    .tag(Pane.logs)
                loginActivityPane
                    .tabItem { Text("Connexions signalées") }
                    .tag(Pane.loginActivity)
                blockListPane
                    .tabItem { Text("Liste de blocage") }
                    .tag(Pane.blockList)
                settingsPane
                    .tabItem { Text("Réglages") }
                    .tag(Pane.settings)
            }
        }
        .toolbar {
            // Le choix du journal et le filtre de niveau accompagnent le champ de recherche
            // dans la barre d'outils, et ne concernent que l'onglet du journal.
            if pane == .logs {
                ToolbarItem {
                    Picker(
                        "Journal",
                        selection: Binding(
                            get: { vm.kind },
                            set: { chosen in Task { await vm.select(chosen) } }
                        )
                    ) {
                        ForEach(vm.availableKinds) { kind in
                            Text(vm.kindText(kind)).tag(kind)
                        }
                    }
                    .help("Choisir le journal à consulter")
                }

                ToolbarItem {
                    Picker("Niveau", selection: $vm.levelFilter) {
                        ForEach(LogsSecurityViewModel.LevelFilter.allCases) { filter in
                            Text(vm.filterText(filter)).tag(filter)
                        }
                    }
                    .help("N’afficher que les entrées de ce niveau")
                }

                ToolbarItem {
                    Menu {
                        Button("Exporter en CSV") { export(as: .csv) }
                        Button("Exporter en HTML") { export(as: .html) }
                    } label: {
                        Label("Exporter", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.isExporting)
                    .help("Enregistrer tout le journal dans un fichier")
                }
            }

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

                Text(vm.kindTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityFocused($focusContent)

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

    /// Les colonnes suivent le journal affiché : un journal de transfert n'attribue pas de
    /// gravité mais donne l'adresse d'origine, l'opération et la taille du fichier. Deux
    /// tableaux distincts plutôt qu'un seul aux colonnes toujours à moitié vides.
    @ViewBuilder
    private var logTable: some View {
        if vm.showsTransferColumns {
            Table(vm.visibleLogs.sorted(using: logOrder), sortOrder: $logOrder) {
                TableColumn("Heure", value: \.sortableDate) { entry in
                    Text(vm.dateText(for: entry))
                }
                TableColumn("Compte", value: \.sortableAccount) { entry in
                    Text(vm.accountText(for: entry))
                }
                TableColumn("Adresse", value: \.sortableAddress) { entry in
                    Text(vm.addressText(for: entry))
                }
                TableColumn("Opération", value: \.sortableOperation) { entry in
                    Text(vm.operationText(for: entry))
                }
                TableColumn("Taille", value: \.sortableSize) { entry in
                    Text(vm.sizeText(for: entry))
                }
                TableColumn("Fichier", value: \.sortableMessage) { entry in
                    Text(entry.message)
                }
            }
        } else {
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
    }

    // MARK: - Connexions signalées

    /// Ce que le Conseiller de sécurité de DSM a relevé : connexions venues d'ailleurs que
    /// d'habitude, et tentatives répétées. Lecture seule — c'est la liste de blocage qui agit.
    @ViewBuilder
    private var loginActivityPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connexions signalées")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if let error = vm.loginActivityError {
                ModuleErrorView(message: error) {
                    Task { await vm.load(announce: true) }
                }
            } else if vm.loginActivity.isEmpty {
                EmptyModuleView(
                    title: "Aucune connexion signalée",
                    systemImage: "checkmark.shield",
                    description: "Le Conseiller de sécurité n’a relevé ni connexion inhabituelle ni tentative répétée."
                )
            } else {
                Table(vm.loginActivity.sorted(using: activityOrder), sortOrder: $activityOrder) {
                    TableColumn("Date", value: \.sortableDate) { event in
                        Text(vm.dateText(for: event))
                    }
                    // Triée par gravité, non par ordre alphabétique.
                    TableColumn("Gravité", value: \.sortableSeverity) { event in
                        Text(vm.severityText(event.severity))
                            .foregroundStyle(color(for: event.severity))
                    }
                    TableColumn("Compte", value: \.sortableAccount) { event in
                        Text(vm.accountText(for: event))
                    }
                    TableColumn("Adresse") { event in
                        Text(vm.addressText(for: event))
                    }
                    TableColumn("Alerte") { event in
                        Text(vm.description(of: event))
                    }
                }

                Text(vm.loginActivitySummary)
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private func color(for severity: LoginActivityEvent.Severity) -> Color {
        switch severity {
        case .high: .readableRed
        case .medium: .readableOrange
        case .low, .other: .primary
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

    /// L'export est produit par le NAS puis écrit là où l'utilisateur le demande. Le panneau
    /// d'enregistrement est celui du système, comme pour les téléchargements de File Station.
    private func export(as format: SystemLogExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = vm.suggestedExportName(for: format)
        panel.canCreateDirectories = true
        panel.message = String(
            localized: "Le NAS exporte tout le journal, et non les seules entrées affichées."
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        VoiceOver.announce(
            String(localized: "Export en cours…"),
            category: .progress,
            priority: .low
        )
        Task {
            let outcome = await vm.export(as: format, to: url)
            VoiceOver.announce(outcome, priority: .high)
        }
    }

    // MARK: - Réglages

    /// Ce qui décide de ce que les autres onglets montrent : quels transferts sont journalisés,
    /// et à partir de quand le NAS bloque une adresse.
    @ViewBuilder
    private var settingsPane: some View {
        Form {
            Section("Journalisation des transferts") {
                Text("Le NAS tient un journal par protocole. Couper un protocole n’efface pas les entrées déjà consignées, mais son journal cesse de s’alimenter.")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)

                ForEach(FileTransferLogging.protocols) { kind in
                    Toggle(
                        isOn: Binding(
                            get: { vm.isTransferLogged(kind) },
                            set: { enabled in
                                Task {
                                    let outcome = await vm.setTransferLogging(kind, enabled: enabled)
                                    VoiceOver.announce(outcome, priority: .high)
                                }
                            }
                        )
                    ) {
                        Text(vm.kindText(kind))
                    }
                    .disabled(vm.isSavingSettings)
                }
            }

            Section("Blocage automatique") {
                if let error = vm.settingsError {
                    Text(error)
                        .foregroundStyle(.readableRed)
                } else if let settings = vm.autoBlock {
                    autoBlockFields(settings)
                } else {
                    Text("Chargement des réglages…")
                        .foregroundStyle(.readableSecondary)
                }
            }
        }
        .formStyle(.grouped)
        .labeledContentStyle(.readable)
    }

    @ViewBuilder
    private func autoBlockFields(_ settings: AutoBlockSettings) -> some View {
        Toggle(
            "Bloquer les adresses après trop d’échecs",
            isOn: Binding(
                get: { settings.isEnabled },
                set: { enabled in
                    var updated = settings
                    updated.isEnabled = enabled
                    save(updated)
                }
            )
        )
        .disabled(vm.isSavingSettings)

        LabeledContent("Tentatives autorisées") {
            Stepper(
                value: Binding(
                    get: { settings.attempts },
                    set: { value in
                        var updated = settings
                        updated.attempts = value
                        save(updated)
                    }
                ),
                in: AutoBlockSettings.attemptsRange
            ) {
                Text(settings.attempts.formatted())
            }
            .disabled(vm.isSavingSettings || !settings.isEnabled)
        }

        LabeledContent("Fenêtre en minutes") {
            Stepper(
                value: Binding(
                    get: { settings.withinMinutes },
                    set: { value in
                        var updated = settings
                        updated.withinMinutes = value
                        save(updated)
                    }
                ),
                in: AutoBlockSettings.withinMinutesRange
            ) {
                Text(settings.withinMinutes.formatted())
            }
            .disabled(vm.isSavingSettings || !settings.isEnabled)
        }

        // DSM code l'absence d'expiration par zéro : l'interrupteur dit la même chose en clair.
        Toggle(
            "Lever le blocage après un délai",
            isOn: Binding(
                get: { settings.expires },
                set: { expires in
                    var updated = settings
                    updated.expiryDays = expires ? AutoBlockSettings.expiryDaysRange.lowerBound : 0
                    save(updated)
                }
            )
        )
        .disabled(vm.isSavingSettings || !settings.isEnabled)

        if settings.expires {
            LabeledContent("Jours avant déblocage") {
                Stepper(
                    value: Binding(
                        get: { settings.expiryDays },
                        set: { value in
                            var updated = settings
                            updated.expiryDays = value
                            save(updated)
                        }
                    ),
                    in: AutoBlockSettings.expiryDaysRange
                ) {
                    Text(settings.expiryDays.formatted())
                }
                .disabled(vm.isSavingSettings)
            }
        }
    }

    private func save(_ settings: AutoBlockSettings) {
        Task {
            let outcome = await vm.save(settings)
            VoiceOver.announce(outcome, priority: .high)
        }
    }

    private var selectedAddresses: [BlockedAddress] {
        vm.blockedAddresses.filter { blockSelection.contains($0.id) }
    }

    /// La couleur double le mot, elle ne le remplace pas : le niveau est toujours écrit.
    private func color(for level: SystemLogEntry.Level?) -> Color {
        switch level {
        case .error: .readableRed
        case .warning: .readableOrange
        case .info, .other, nil: .primary
        }
    }
}
