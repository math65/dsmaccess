//
//  LogsSecurityView.swift
//  dsmaccess
//
//  The NAS system log and the auto-block block list, as sortable tables.
//
//  Two tabs rather than two stacked sections: the log is browsed, the block list is acted
//  on, and mixing the two forced the user to cross one to reach the other.
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
                    // The field goes in the toolbar, as in every other module. It is placed on
                    // this tab only: the search goes to the NAS, which filters the whole log,
                    // and has nothing to do for a block list of a few rows.
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
            // The log picker and the level filter sit alongside the search field in the
            // toolbar, and concern the log tab only.
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
                    OperationFailures.shared.present(outcome, from: .logsSecurity)
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

    // MARK: - Log

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
                                    OperationFailures.shared.present(outcome, from: .logsSecurity)
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

    /// The columns follow the displayed log: a transfer log assigns no severity but gives the
    /// source address, the operation and the file size. Two distinct tables rather than a
    /// single one whose columns are always half empty.
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
            .accessibilityLabel("common.label.log")
        } else {
            Table(vm.visibleLogs.sorted(using: logOrder), sortOrder: $logOrder) {
                TableColumn("logs.column.time", value: \.sortableDate) { entry in
                    Text(vm.dateText(for: entry))
                }
                // Sorted by severity and not alphabetically: "Error" must come after
                // "Warning".
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
            .accessibilityLabel("common.label.log")
        }
    }

    // MARK: - Flagged sign-ins

    /// What DSM's Security Advisor noticed: sign-ins coming from somewhere other than usual,
    /// and repeated attempts. Read-only — the block list is what acts.
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
                    // Sorted by severity, not alphabetically.
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
                .accessibilityLabel("logs.tab.flagged_signins")

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

    // MARK: - Block list

    @ViewBuilder
    private var blockListPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("logs.tab.block_list")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            if let error = vm.blockedAddressesError {
                // An account without administration privilege is denied this list: say so,
                // rather than showing an empty list that would read as a NAS with no blocked
                // address.
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
                .accessibilityLabel("logs.tab.block_list")

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

    /// The export is produced by the NAS then written where the user asks. The save panel is
    /// the system one, as for File Station downloads.
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
            OperationFailures.shared.present(outcome, from: .logsSecurity)
        }
    }

    // MARK: - Settings

    /// What decides what the other tabs show: which transfers are logged, and at what point
    /// the NAS blocks an address.
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
                                    OperationFailures.shared.present(outcome, from: .logsSecurity)
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
        .accessibilityLabel("logs.settings.form.label")
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

        // DSM encodes "never expires" as zero: the switch says the same thing in plain words.
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
            OperationFailures.shared.present(outcome, from: .logsSecurity)
        }
    }

    private var selectedAddresses: [BlockedAddress] {
        vm.blockedAddresses.filter { blockSelection.contains($0.id) }
    }

    /// The colour backs up the word, it does not replace it: the level is always written out.
    private func color(for level: SystemLogEntry.Level?) -> Color {
        switch level {
        case .error: .readableRed
        case .warning: .readableOrange
        case .info, .other, nil: .primary
        }
    }
}
