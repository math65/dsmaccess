//
//  LogsSecurityView.swift
//  dsmaccess
//
//  Consultation des journaux et des protections de sécurité exposées par DSM.
//

import SwiftUI

struct LogsSecurityView: View {
    private enum Tab: Hashable { case logs, security }
    private enum Severity { case error, warning, info }
    private enum LevelFilter: String, CaseIterable, Identifiable {
        case all, error, warning, info
        var id: Self { self }
    }

    @State private var viewModel: LogsSecurityViewModel
    @State private var selectedTab = Tab.logs
    @State private var searchText = ""
    @State private var levelFilter = LevelFilter.all
    @State private var pendingUnblock: BlockedAddress?
    @AccessibilityFocusState private var contentFocused: Bool

    private let capabilities: DSMCapabilities

    init(session: SessionStore) {
        capabilities = session.capabilities
        _viewModel = State(initialValue: LogsSecurityViewModel(session: session))
    }

    var body: some View {
        content
            .searchable(text: $searchText, prompt: searchPrompt)
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
            .confirmationDialog(
                "Débloquer cette adresse ?",
                isPresented: Binding(
                    get: { pendingUnblock != nil },
                    set: { if !$0 { pendingUnblock = nil } }
                ),
                presenting: pendingUnblock
            ) { blockedAddress in
                Button("Débloquer \(blockedAddress.address)", role: .destructive) {
                    Task { await unblock(blockedAddress) }
                }
                .help(String(localized: "Débloquer \(blockedAddress.address)"))
                Button("Annuler", role: .cancel) { }
                    .help("Conserver cette adresse bloquée")
            } message: { blockedAddress in
                Text("Les nouvelles connexions provenant de \(blockedAddress.address) seront à nouveau autorisées par le blocage automatique.")
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.logs.isEmpty {
            ModuleLoadingView("Chargement des journaux et protections…")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else {
            TabView(selection: $selectedTab) {
                logsView
                    .tabItem { Label("Journaux", systemImage: "doc.text.magnifyingglass") }
                    .tag(Tab.logs)
                securityView
                    .tabItem { Label("Sécurité", systemImage: "lock.shield") }
                    .tag(Tab.security)
            }
            .accessibilityFocused($contentFocused)
        }
    }

    @ViewBuilder
    private var logsView: some View {
        if filteredLogs.isEmpty {
            EmptyModuleView(
                title: viewModel.logs.isEmpty ? "Journal vide" : "Aucun résultat",
                systemImage: "doc.text.magnifyingglass",
                description: viewModel.logs.isEmpty
                    ? "Aucune entrée de journal n’est disponible."
                    : "Modifiez la recherche ou le filtre de niveau."
            )
        } else {
            List(filteredLogs) { entry in
                logRow(entry)
            }
            .accessibilityLabel("Journal système")
        }
    }

    private var securityView: some View {
        List {
            Section("Interfaces de protection") {
                securityFeature(
                    title: "Blocage automatique",
                    systemImage: "hand.raised",
                    available: supportsAutoBlock
                )
                securityFeature(
                    title: "Pare-feu",
                    systemImage: "firewall",
                    available: capabilities.supports(prefix: "SYNO.Core.Security.Firewall")
                )
                securityFeature(
                    title: "Analyse de sécurité",
                    systemImage: "checkmark.shield",
                    available: capabilities.supports(prefix: "SYNO.Core.SecurityScan")
                )
                securityFeature(
                    title: "Protection des comptes",
                    systemImage: "person.badge.shield.checkmark",
                    available: capabilities.supports(prefix: "SYNO.Core.Security.Account")
                        || capabilities.supports(prefix: "SYNO.Core.SmartBlock.User")
                )
            }

            Section("Adresses bloquées") {
                if let message = viewModel.blockedAddressesError {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Erreur : \(message)")
                } else if !supportsAutoBlock {
                    Text("La liste de blocage n’est pas exposée par ce NAS.")
                        .foregroundStyle(.secondary)
                } else if filteredBlockedAddresses.isEmpty {
                    Text(searchText.isEmpty ? "Aucune adresse bloquée" : "Aucun résultat")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredBlockedAddresses) { address in
                        blockedAddressRow(address)
                            .contextMenu {
                                Button("Débloquer…", role: .destructive) { pendingUnblock = address }
                                    .disabled(viewModel.busyAddresses.contains(address.address))
                                    .help(String(localized: "Débloquer \(address.address)"))
                            }
                    }
                }
            }
        }
        .accessibilityLabel("Sécurité")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if selectedTab == .logs {
            ToolbarItem {
                Menu {
                    Picker("Niveau", selection: $levelFilter) {
                        Text("Tous les niveaux").tag(LevelFilter.all)
                        Text("Erreurs").tag(LevelFilter.error)
                        Text("Avertissements").tag(LevelFilter.warning)
                        Text("Informations").tag(LevelFilter.info)
                    }
                    .help("Choisir le niveau de journal à afficher")
                } label: {
                    Label("Filtrer le journal", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Filtrer le journal par niveau")
            }
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .help("Actualiser les journaux et protections")
        }
    }

    private func logRow(_ entry: SystemLogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: levelIcon(entry.level))
                .foregroundStyle(levelColor(entry.level))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.message).fontWeight(.medium)
                Text(logMetadata(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(logAccessibilityLabel(entry))
    }

    private func securityFeature(
        title: LocalizedStringKey,
        systemImage: String,
        available: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(available ? "Interface disponible" : "Non exposée")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func blockedAddressRow(_ blockedAddress: BlockedAddress) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(blockedAddress.address).fontWeight(.medium)
                Text(blockedAddressDetail(blockedAddress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Débloquer…") { pendingUnblock = blockedAddress }
                .disabled(viewModel.busyAddresses.contains(blockedAddress.address))
                .accessibilityLabel("Débloquer \(blockedAddress.address)")
                .help(String(localized: "Débloquer \(blockedAddress.address)"))
        }
        .accessibilityElement(children: .contain)
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.summary)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    private var filteredLogs: [SystemLogEntry] {
        viewModel.logs.filter { entry in
            levelMatches(entry) && searchMatches(entry)
        }
    }

    private var filteredBlockedAddresses: [BlockedAddress] {
        guard !searchText.isEmpty else { return viewModel.blockedAddresses }
        return viewModel.blockedAddresses.filter {
            $0.address.localizedStandardContains(searchText)
                || ($0.reason?.localizedStandardContains(searchText) == true)
        }
    }

    private var supportsAutoBlock: Bool {
        capabilities.supports("SYNO.Core.Security.AutoBlock")
            || capabilities.supports("SYNO.Core.SmartBlock.Untrusted")
    }

    private var searchPrompt: LocalizedStringKey {
        selectedTab == .logs ? "Rechercher dans le journal" : "Rechercher une adresse bloquée"
    }

    private func levelMatches(_ entry: SystemLogEntry) -> Bool {
        guard levelFilter != .all else { return true }
        let level = entry.level.lowercased()
        return switch levelFilter {
        case .all: true
        case .error: level.contains("error") || level.contains("critical") || level == "err"
        case .warning: level.contains("warn")
        case .info: level.contains("info") || level.contains("notice")
        }
    }

    private func searchMatches(_ entry: SystemLogEntry) -> Bool {
        guard !searchText.isEmpty else { return true }
        return entry.message.localizedStandardContains(searchText)
            || (entry.user?.localizedStandardContains(searchText) == true)
            || (entry.address?.localizedStandardContains(searchText) == true)
            || (entry.category?.localizedStandardContains(searchText) == true)
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "Chargement des journaux et de la sécurité…"),
            category: .progress,
            priority: .low
        )
        await viewModel.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { contentFocused = true }
        }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .result : .error
        )
    }

    private func unblock(_ blockedAddress: BlockedAddress) async {
        VoiceOver.announce(await viewModel.unblock(blockedAddress), priority: .high)
    }

    private func logMetadata(_ entry: SystemLogEntry) -> String {
        [timestampText(entry.timestamp), entry.category, entry.user, entry.address]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func logAccessibilityLabel(_ entry: SystemLogEntry) -> String {
        [levelText(entry.level), timestampText(entry.timestamp), entry.message, entry.user, entry.address]
            .compactMap { $0 }
            .formatted(.list(type: .and))
    }

    private func blockedAddressDetail(_ blockedAddress: BlockedAddress) -> String {
        [blockedAddress.reason, blockedAddress.expiresAt.map { String(localized: "expiration \($0)") }]
            .compactMap { $0 }
            .joined(separator: " · ")
            .ifEmpty(String(localized: "Blocage sans expiration indiquée"))
    }

    private func timestampText(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) {
            return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .standard)
        }
        return value
    }

    private func levelText(_ level: String) -> String {
        switch severity(level) {
        case .error: String(localized: "Erreur")
        case .warning: String(localized: "Avertissement")
        case .info: String(localized: "Information")
        }
    }

    private func levelIcon(_ level: String) -> String {
        switch severity(level) {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch severity(level) {
        case .error: .red
        case .warning: .orange
        case .info: .secondary
        }
    }

    private func severity(_ level: String) -> Severity {
        let value = level.lowercased()
        if value.contains("error") || value.contains("critical") || value == "err" { return .error }
        if value.contains("warn") { return .warning }
        return .info
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String { isEmpty ? replacement : self }
}
