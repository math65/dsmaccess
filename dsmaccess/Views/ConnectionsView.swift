//
//  ConnectionsView.swift
//  dsmaccess
//
//  “Connections” tab of the resource monitor, as a sortable table: every value stays in its
//  column, and the headers sort with a single click as everywhere else on the Mac.
//  Cutting a session is confirmed before being sent, and its result announced.
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
                Button("common.button.cancel", role: .cancel) { }
                    .help("connections.disconnect.confirm.cancel")
            } message: {
                Text(kickMessage)
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.connections.isEmpty {
            ModuleLoadingView("connections.loading")
        } else if let error = vm.errorMessage, vm.connections.isEmpty {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
        } else if vm.connections.isEmpty {
            ContentUnavailableView(
                "connections.empty.title",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("connections.empty.description")
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("connections.table.label")
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
                    TableColumn("common.column.account", value: \.sortableAccount) { connection in
                        Text(vm.accountText(for: connection))
                    }
                    TableColumn("common.column.protocol", value: \.sortableType) { connection in
                        Text(connection.type ?? String(localized: "connections.protocol.unknown"))
                    }
                    TableColumn("common.column.address", value: \.sortableAddress) { connection in
                        Text(connection.address ?? String(localized: "connections.address.unknown"))
                    }
                    TableColumn("common.column.resource", value: \.sortableDescription) { connection in
                        Text(connection.descriptionText ?? "—")
                    }
                    TableColumn("connections.column.opened", value: \.sortableDate) { connection in
                        Text(vm.openedAtText(for: connection))
                    }
                    // Three values DSM does not display. “Client” and “Place” stay empty on a
                    // local access — the NAS only fills them in for certain sessions — hence
                    // the dash, consistent with the other columns of this module.
                    TableColumn("connections.column.client", value: \.sortableUserAgent) { connection in
                        Text(vm.clientText(for: connection))
                    }
                    TableColumn("common.column.place", value: \.sortableLocation) { connection in
                        Text(vm.locationText(for: connection))
                    }
                    TableColumn("connections.column.two_step", value: \.sortableTwoFactor) { connection in
                        Text(vm.twoFactorText(for: connection))
                    }
                    // No “current session” column: verified on DSM 7.4, the NAS only raises
                    // `is_current_connected` for its own web client. Queried by the app, it
                    // marks no row — the column would contain nothing but dashes.
                }
                .accessibilityLabel("connections.table.label")
                .contextMenu(forSelectionType: String.self) { ids in
                    let targets = connections(for: ids)
                    if targets.contains(where: vm.canKick) {
                        Button("connections.button.disconnect", role: .destructive) {
                            pendingKick = targets.filter(vm.canKick)
                        }
                    }
                }

                actionBar

                Text("connections.table.footer")
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
            .help("connections.button.disconnect.hint")
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

    /// The label carries the count: without it, the button announces itself as “Disconnect”
    /// without saying what it applies to, and nothing distinguishes one session from six.
    private var kickButtonLabel: String {
        let count = selectedConnections.filter(vm.canKick).count
        return count <= 1
            ? String(localized: "connections.button.disconnect_selected_single")
            : String(
                localized: "connections.button.disconnect_selected_multiple",
                defaultValue: "Disconnect the \(count) selected sessions…"
            )
    }

    private var kickTitle: String {
        pendingKick.count <= 1
            ? String(localized: "connections.disconnect.single.confirm.title")
            : String(
                localized: "connections.disconnect.multiple.confirm.title",
                defaultValue: "Disconnect these \(pendingKick.count) sessions?"
            )
    }

    private var kickConfirmationLabel: String {
        guard let only = pendingKick.first, pendingKick.count == 1 else {
            return String(
                localized: "connections.disconnect.multiple.confirm.button",
                defaultValue: "Disconnect the \(pendingKick.count) sessions"
            )
        }
        return String(
            localized: "connections.row.disconnect.label",
            defaultValue: "Disconnect \(vm.accountText(for: only))’s session"
        )
    }

    /// The confirmation names the targeted sessions and says what happens: a transfer in
    /// progress on those sessions is interrupted. The warning about one's own session is not
    /// a certainty — the NAS does not say which one belongs to the app — and says so.
    private var kickMessage: String {
        var sentences: [String] = []
        if let only = pendingKick.first, pendingKick.count == 1 {
            sentences.append(
                String(
                    localized: "connections.disconnect.single.confirm.message",
                    defaultValue: "\(vm.accountText(for: only))’s session from \(only.address ?? String(localized: "connections.address.unknown.inline")) will be closed, and any transfer in progress on it interrupted."
                )
            )
        } else {
            let accounts = pendingKick.map { vm.accountText(for: $0) }
            sentences.append(
                String(
                    localized: "connections.disconnect.multiple.confirm.message",
                    defaultValue: "These sessions will be closed and any transfer in progress interrupted. Accounts affected: \(accounts.formatted(.list(type: .and)))."
                )
            )
        }
        if vm.mayCloseOwnSession(pendingKick) {
            // Two complete sentences rather than one phrasing covering both cases: “one of
            // these sessions” in front of a single selected row sounds like a bug, and a
            // patched-together agreement would translate badly.
            sentences.append(
                pendingKick.count == 1
                    ? String(
                        localized: "connections.disconnect.single.confirm.self_warning"
                    )
                    : String(
                        localized: "connections.disconnect.multiple.confirm.self_warning"
                    )
            )
        }
        return sentences.joined(separator: " ")
    }

    private func kick(_ targets: [NASConnection]) async {
        let outcome = await vm.kick(targets)
        // The list has been reloaded: the retained identifiers no longer point to anything,
        // and a phantom selection would re-arm the button on sessions that are gone.
        selection = []
        OperationFailures.shared.present(outcome, from: .resourceMonitor) { focusContent = true }
    }
}
