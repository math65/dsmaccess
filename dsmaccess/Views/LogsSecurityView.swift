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
                    .searchable(text: $vm.searchText, prompt: "common.field.search_log")
                    .tabItem { Text("common.label.log") }
                    .tag(Pane.logs)
                loginActivityPane
                    .tabItem { Text("logs.tab.flagged_signins") }
                    .tag(Pane.loginActivity)
                blockListPane
                    .tabItem { Text("logs.tab.block_list") }
                    .tag(Pane.blockList)
                settingsPane
                    .tabItem { Text("logs.settings.title") }
                    .tag(Pane.settings)
            }
        }
        .toolbar {
            // Le choix du journal et le filtre de niveau accompagnent le champ de recherche
            // dans la barre d'outils, et ne concernent que l'onglet du journal.
            if pane == .logs {
                ToolbarItem {
                    Picker(
                        "common.label.log",
                        selection: Binding(
                            get: { vm.kind },
                            set: { chosen in Task { await vm.select(chosen) } }
                        )
                    ) {
                        ForEach(vm.availableKinds) { kind in
                            Text(vm.kindText(kind)).tag(kind)
                        }
                    }
                    .help("logs.log_picker.hint")
                }

                ToolbarItem {
                    Picker("common.column.level", selection: $vm.levelFilter) {
                        ForEach(LogsSecurityViewModel.LevelFilter.allCases) { filter in
                            Text(vm.filterText(filter)).tag(filter)
                        }
                    }
                    .help("logs.filter.level.hint")
                }

                ToolbarItem {
                    Menu {
                        Button("logs.export.csv") { export(as: .csv) }
                        Button("logs.export.html") { export(as: .html) }
                    } label: {
                        Label("logs.export.menu", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.isExporting)
                    .help("logs.export.hint")
                }
            }

            ToolbarItem {
                Button {
                    Task {
                        await vm.load(announce: true)
                    }
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("logs.refresh.label")
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
            Button("logs.security.unblock.button", role: .destructive) {
                let addresses = pendingUnblock
                pendingUnblock = []
                Task {
                    let outcome = await vm.unblock(addresses)
                    VoiceOver.announce(outcome, priority: .high)
                }
            }
            Button("common.button.cancel", role: .cancel) { pendingUnblock = [] }
        } message: {
            Text("logs.security.unblock.confirm.description")
        }
    }

    private var unblockTitle: String {
        if pendingUnblock.count == 1, let only = pendingUnblock.first {
            return String(localized: "logs.security.unblock.confirm.single", defaultValue: "Unblock the address \(only.address)?")
        }
        return String(localized: "logs.security.unblock.confirm.multiple", defaultValue: "Unblock \(pendingUnblock.count) addresses?")
    }

    // MARK: - Journal

    @ViewBuilder
    private var logsPane: some View {
        if vm.isLoading && vm.logs.isEmpty {
            ModuleLoadingView("common.status.loading_log")
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
                        title: "logs.entries.empty",
                        systemImage: "doc.text.magnifyingglass",
                        description: vm.logs.isEmpty
                            ? "logs.search.empty.description"
                            : "logs.entries.empty.description"
                    )
                } else {
                    logTable
                }

                HStack(spacing: 12) {
                    Text(vm.summary)
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)

                    if vm.canLoadMore {
                        Button("logs.load_more.button") {
                            Task {
                                if let outcome = await vm.loadMore() {
                                    VoiceOver.announce(outcome, priority: .high)
                                }
                            }
                        }
                        .disabled(vm.isLoadingMore)
                        .accessibilityHint("logs.load_more.hint")
                        .help("logs.load_more.label")
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
                TableColumn("logs.column.time", value: \.sortableDate) { entry in
                    Text(vm.dateText(for: entry))
                }
                TableColumn("common.column.account", value: \.sortableAccount) { entry in
                    Text(vm.accountText(for: entry))
                }
                TableColumn("common.column.address", value: \.sortableAddress) { entry in
                    Text(vm.addressText(for: entry))
                }
                TableColumn("common.column.operation", value: \.sortableOperation) { entry in
                    Text(vm.operationText(for: entry))
                }
                TableColumn("common.column.size", value: \.sortableSize) { entry in
                    Text(vm.sizeText(for: entry))
                }
                TableColumn("common.value.file", value: \.sortableMessage) { entry in
                    Text(entry.message)
                }
            }
        } else {
            Table(vm.visibleLogs.sorted(using: logOrder), sortOrder: $logOrder) {
                TableColumn("logs.column.time", value: \.sortableDate) { entry in
                    Text(vm.dateText(for: entry))
                }
                // Triée par gravité et non par ordre alphabétique : « Erreur » doit se ranger
                // après « Avertissement ».
                TableColumn("common.column.level", value: \.sortableLevel) { entry in
                    Text(vm.levelText(entry.level))
                        .foregroundStyle(color(for: entry.level))
                }
                TableColumn("logs.column.category") { entry in
                    Text(vm.categoryText(for: entry))
                }
                TableColumn("common.column.account", value: \.sortableAccount) { entry in
                    Text(vm.accountText(for: entry))
                }
                TableColumn("logs.column.event", value: \.sortableMessage) { entry in
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
            Text("logs.tab.flagged_signins")
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
                    title: "logs.flagged_signins.empty",
                    systemImage: "checkmark.shield",
                    description: "logs.security.alerts.empty.description"
                )
            } else {
                Table(vm.loginActivity.sorted(using: activityOrder), sortOrder: $activityOrder) {
                    TableColumn("common.column.date", value: \.sortableDate) { event in
                        Text(vm.dateText(for: event))
                    }
                    // Triée par gravité, non par ordre alphabétique.
                    TableColumn("common.column.severity", value: \.sortableSeverity) { event in
                        Text(vm.severityText(event.severity))
                            .foregroundStyle(color(for: event.severity))
                    }
                    TableColumn("common.column.account", value: \.sortableAccount) { event in
                        Text(vm.accountText(for: event))
                    }
                    TableColumn("common.column.address") { event in
                        Text(vm.addressText(for: event))
                    }
                    TableColumn("common.level.alert") { event in
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
            Text("logs.tab.block_list")
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
                    title: "logs.block_list.empty",
                    systemImage: "hand.raised",
                    description: "logs.block_list.empty.description"
                )
            } else {
                Table(
                    vm.blockedAddresses.sorted(using: blockOrder),
                    selection: $blockSelection,
                    sortOrder: $blockOrder
                ) {
                    TableColumn("common.column.address", value: \.address) { address in
                        Text(address.address)
                    }
                    TableColumn("logs.block_list.column.blocked_at", value: \.sortableBlockedAt) { address in
                        Text(vm.blockedAtText(for: address))
                    }
                    TableColumn("common.column.expiration", value: \.sortableExpiry) { address in
                        Text(vm.expiryText(for: address))
                    }
                    TableColumn("common.column.place", value: \.sortableCountry) { address in
                        Text(vm.countryText(for: address))
                    }
                }

                HStack {
                    Button("logs.security.unblock.button", role: .destructive) {
                        pendingUnblock = selectedAddresses
                    }
                    .disabled(selectedAddresses.isEmpty || !selectedAddresses.allSatisfy(vm.canUnblock))
                    .help("logs.security.unblock.hint")

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
            localized: "logs.export.footer"
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = url.startAccessingSecurityScopedResource()
        VoiceOver.announce(
            String(localized: "logs.export.progress"),
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
            Section("logs.settings.transfer_logging") {
                Text("logs.settings.transfer_logging.description")
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

            Section("logs.auto_block.title") {
                if let error = vm.settingsError {
                    Text(error)
                        .foregroundStyle(.readableRed)
                } else if let settings = vm.autoBlock {
                    autoBlockFields(settings)
                } else {
                    Text("logs.settings.loading")
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
            "logs.auto_block.enable.label",
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

        LabeledContent("logs.auto_block.attempts.label") {
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

        LabeledContent("logs.security.autoblock.window_minutes") {
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
            "logs.auto_block.expire.label",
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
            LabeledContent("logs.auto_block.expire_days.label") {
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
