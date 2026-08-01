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
    @State private var sort = FileStationSharingSort.name
    @State private var ascending = true
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
        .frame(width: 780, height: 570)
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

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("common.label.sort_by", selection: $sort) {
                ForEach(FileStationSharingSort.allCases, id: \.self) { value in
                    Text(value.localizedTitle).tag(value)
                }
            }
            .frame(maxWidth: 230)
            Toggle("common.sort.ascending", isOn: $ascending)
            Button("common.button.apply") { Task { await loadShareLinks(forceRefresh: false) } }
                .disabled(vm.isLoadingShareLinks || isMutating)
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
            List(vm.shareLinks, selection: $selection) { link in
                row(for: link)
                    .tag(link.id)
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

    private func row(for link: SharingLink) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(link.name ?? link.path ?? link.url)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(link.url)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(linkSummary(link))
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
            }
            Spacer()
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
        .accessibilityElement(children: .contain)
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

    private func linkSummary(_ link: SharingLink) -> String {
        var parts = [String]()
        if let status = link.status { parts.append(status) }
        if link.hasPassword == true { parts.append(String(localized: "share_links.row.password_protected")) }
        if let available = link.availableDate {
            parts.append(String(localized: "share_links.row.available_on", defaultValue: "Available on \(available)"))
        }
        if let expiration = link.expirationDate {
            parts.append(String(localized: "share_links.row.expires_on", defaultValue: "Expires on \(expiration)"))
        }
        return parts.isEmpty ? String(localized: "share_links.row.no_restriction") : parts.formatted(.list(type: .and))
    }

    private func loadShareLinks(forceRefresh: Bool) async {
        operationError = nil
        await vm.loadShareLinks(
            options: FileStationSharingListOptions(
                sortBy: sort,
                sortDirection: ascending ? .ascending : .descending,
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

private extension FileStationSharingSort {
    var localizedTitle: String {
        switch self {
        case .id: String(localized: "common.column.identifier")
        case .name: String(localized: "common.column.name")
        case .isFolder: String(localized: "common.column.kind")
        case .path: String(localized: "common.column.path")
        case .expirationDate: String(localized: "common.column.expiration_date")
        case .availableDate: String(localized: "common.column.available_date")
        case .status: String(localized: "common.column.status")
        case .hasPassword: String(localized: "common.label.password_protection")
        case .url: "URL"
        case .owner: String(localized: "common.column.owner")
        }
    }
}
