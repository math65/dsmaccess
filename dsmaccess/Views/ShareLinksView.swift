//
//  ShareLinksView.swift
//  dsmaccess
//
//  Full management of File Station sharing links.
//

import AppKit
import SwiftUI

struct ShareLinksView: View {
    @Bindable var vm: FileBrowserViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<String>()
    @State private var order = [KeyPathComparator(\SharingLink.sortableName, order: .forward)]
    @State private var editingLink: SharingLink?
    @State private var detailsLink: SharingLink?
    @State private var pendingDelete = [SharingLink]()
    @State private var confirmsInvalidCleanup = false
    @State private var isMutating = false
    @State private var operationError: String?
    @AccessibilityFocusState private var focusTitle: Bool
    @AccessibilityFocusState private var focusStatus: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 940, height: 570)
        .task {
            focusTitle = true
            await loadShareLinks(forceRefresh: false)
        }
        .sheet(item: $editingLink) { link in
            ShareLinkEditorSheet(link: link) { changes in
                await vm.editShareLink(link, changes: changes)
            }
        }
        .sheet(item: $detailsLink) { link in
            ShareLinkDetailsSheet(vm: vm, link: link)
        }
        .alert(
            deleteTitle,
            isPresented: Binding(
                get: { !pendingDelete.isEmpty },
                set: { if !$0 { pendingDelete.removeAll() } }
            )
        ) {
            Button("common.button.delete", role: .destructive) { Task { await deletePendingLinks() } }
            Button("common.button.cancel", role: .cancel) { pendingDelete.removeAll() }
        } message: {
            Text(deleteMessage)
        }
        .alert("share_links.clear_invalid.confirm.title", isPresented: $confirmsInvalidCleanup) {
            Button("common.button.clear", role: .destructive) { Task { await clearInvalidLinks() } }
            Button("common.button.cancel", role: .cancel) {}
        } message: {
            Text("share_links.clear_invalid.confirm.message")
        }
    }

    private var header: some View {
        HStack {
            Text("common.action.share_links")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)
            Spacer()
            if vm.isLoadingShareLinks || isMutating {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("share_links.operation.progress")
            }
            Button("common.button.close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .help("share_links.close.button")
        }
        .padding()
    }

    // The sort menu, its direction switch and its Apply button are gone: the table sorts on
    // its own headers, where the values are, instead of from a separate set of controls that
    // had to be applied before anything moved.
    private var controls: some View {
        HStack(spacing: 16) {
            Spacer()
            Button("common.button.refresh", systemImage: "arrow.clockwise") {
                Task { await loadShareLinks(forceRefresh: true) }
            }
            .disabled(vm.isLoadingShareLinks || isMutating)
            .help("share_links.refresh.button")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let operationError {
            VStack(spacing: 12) {
                Text(operationError)
                    .foregroundStyle(.readableRed)
                    .multilineTextAlignment(.center)
                    .accessibilityFocused($focusStatus)
                Button("common.button.dismiss_error") { self.operationError = nil }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.isLoadingShareLinks && vm.shareLinks.isEmpty {
            ModuleLoadingView("share_links.loading")
                .accessibilityFocused($focusStatus)
        } else if let error = vm.shareLinksError {
            VStack(spacing: 12) {
                Text(error).foregroundStyle(.readableRed).multilineTextAlignment(.center)
                Button("common.button.retry") { Task { await loadShareLinks(forceRefresh: true) } }
                    .help("share_links.error.retry.button")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if vm.shareLinks.isEmpty {
            ContentUnavailableView(
                "share_links.empty.title",
                systemImage: "link",
                description: Text("share_links.empty.description")
            )
            .accessibilityFocused($focusStatus)
        } else {
            Table(vm.shareLinks.sorted(using: order), selection: $selection, sortOrder: $order) {
                TableColumn("common.column.name", value: \.sortableName) { link in
                    Text(link.displayName)
                }
                TableColumn("common.column.url", value: \.url) { link in
                    Text(link.url)
                }
                TableColumn("common.column.owner", value: \.sortableOwner) { link in
                    Text(link.owner ?? "—")
                }
                TableColumn("common.column.password", value: \.sortablePassword) { link in
                    Text(link.hasPassword == true
                        ? String(localized: "common.answer.yes")
                        : String(localized: "common.answer.no"))
                }
                TableColumn("common.column.status", value: \.sortableStatus) { link in
                    Text(link.status ?? "—")
                }
                TableColumn("common.column.available_date", value: \.sortableAvailableDate) { link in
                    Text(link.availableDate ?? "—")
                }
                TableColumn("common.column.expiration_date", value: \.sortableExpirationDate) { link in
                    Text(link.expirationDate ?? "—")
                }
                // The four per-row buttons stay in the table rather than moving to a context
                // menu: they were already reachable one by one here, and a menu would put them
                // one step further away.
                TableColumn("common.column.actions") { link in
                    rowActions(for: link)
                }
            }
            .accessibilityLabel("share_links.title")
        }
    }

    private var footer: some View {
        HStack {
            Button("share_links.clear_invalid.button", role: .destructive) {
                confirmsInvalidCleanup = true
            }
            .disabled(isMutating || vm.isLoadingShareLinks)
            .help("share_links.clear_invalid.hint")
            Spacer()
            Button("share_links.delete_selection.button", role: .destructive) {
                pendingDelete = selectedLinks
            }
            .disabled(selection.isEmpty || isMutating)
            Button("common.button.close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private func rowActions(for link: SharingLink) -> some View {
        HStack(spacing: 6) {
            Button("common.button.details", systemImage: "info.circle") { detailsLink = link }
                .labelStyle(.iconOnly)
                .help("share_links.row.details.button")
            Button("common.button.edit", systemImage: "pencil") { editingLink = link }
                .labelStyle(.iconOnly)
                .help("share_links.row.edit.button")
            Button("common.button.copy", systemImage: "doc.on.clipboard") { copyToClipboard(link.url) }
                .labelStyle(.iconOnly)
                .help("share_links.row.copy.button")
            Button("common.button.delete", systemImage: "trash", role: .destructive) {
                pendingDelete = [link]
            }
            .labelStyle(.iconOnly)
            .help("share_links.row.delete.button")
        }
        .buttonStyle(.borderless)
    }

    private var selectedLinks: [SharingLink] {
        vm.shareLinks.filter { selection.contains($0.id) }
    }

    private var deleteTitle: String {
        pendingDelete.count == 1
            ? String(localized: "share_links.delete.confirm.title")
            : String(localized: "share_links.delete_selection.confirm.title", defaultValue: "Delete \(pendingDelete.count) sharing links?")
    }

    private var deleteMessage: String {
        if pendingDelete.count == 1, let link = pendingDelete.first {
            return String(
                localized: "share_links.delete.confirm.message",
                defaultValue: "The link to “\(link.name ?? link.path ?? link.url)” will stop working immediately."
            )
        }
        return String(
            localized: "share_links.delete_selection.confirm.message"
        )
    }

    private func loadShareLinks(forceRefresh: Bool) async {
        operationError = nil
        // The NAS is asked for a stable order; the column the user picked is applied here,
        // on the loaded links, so sorting never costs a round trip.
        await vm.loadShareLinks(
            options: FileStationSharingListOptions(
                sortBy: .name,
                sortDirection: .ascending,
                forceRefresh: forceRefresh
            )
        )
        guard !Task.isCancelled else { return }
        selection.formIntersection(vm.shareLinks.map(\.id))
        if vm.shareLinksError == nil {
            focusTitle = true
        } else {
            focusStatus = true
        }
        VoiceOver.announce(
            shareLinksAnnouncement,
            category: vm.shareLinksError == nil ? .result : .error
        )
    }

    private var shareLinksAnnouncement: String {
        if let error = vm.shareLinksError { return error }
        return String(localized: "share_links.count", defaultValue: "Sharing links: \(vm.shareLinks.count)")
    }

    private func deletePendingLinks() async {
        let links = pendingDelete
        pendingDelete.removeAll()
        isMutating = true
        defer { isMutating = false }
        let outcome = await vm.deleteShareLinks(links)
        selection.subtract(links.map(\.id))
        handle(outcome)
    }

    private func clearInvalidLinks() async {
        isMutating = true
        defer { isMutating = false }
        handle(await vm.clearInvalidShareLinks())
    }

    private func handle(_ outcome: DSMOperationOutcome) {
        if case .failure(let message) = outcome {
            operationError = message
            focusStatus = true
        }
        VoiceOver.announce(outcome, priority: .high)
    }

    private func copyToClipboard(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        VoiceOver.announce(String(localized: "common.status.link_copied"))
    }
}
