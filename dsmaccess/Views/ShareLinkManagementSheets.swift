//
//  ShareLinkManagementSheets.swift
//  dsmaccess
//
//  Details and editing of a File Station share link.
//

import AppKit
import SwiftUI

struct ShareLinkEditorSheet: View {
    let link: SharingLink
    let save: (FileStationShareLinkChanges) async -> DSMOperationOutcome

    @Environment(\.dismiss) private var dismiss
    @State private var editsPassword = false
    @State private var password = ""
    @State private var editsAvailableDate = false
    @State private var hasAvailableDate: Bool
    @State private var availableDate: Date
    @State private var editsExpirationDate = false
    @State private var hasExpirationDate: Bool
    @State private var expirationDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusError: Bool

    init(
        link: SharingLink,
        save: @escaping (FileStationShareLinkChanges) async -> DSMOperationOutcome
    ) {
        self.link = link
        self.save = save
        let available = sharingDate(link.availableDate)
        let expiration = sharingDate(link.expirationDate)
        _hasAvailableDate = State(initialValue: available != nil)
        _availableDate = State(initialValue: available ?? .now)
        _hasExpirationDate = State(initialValue: expiration != nil)
        _expirationDate = State(
            initialValue: expiration ?? Date.now.addingTimeInterval(604_800)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("share_link.edit.title")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            Divider()

            Form {
                Section("share_links.detail.link") {
                    LabeledContent("share_links.detail.item", value: link.name ?? link.path ?? link.url)
                }

                Section("common.field.password") {
                    Toggle("share_link.password.action", isOn: $editsPassword)
                    if editsPassword {
                        SecureField("common.field.new_password", text: $password)
                        Text("share_links.edit.password.hint")
                            .font(.callout)
                            .foregroundStyle(.readableSecondary)
                    }
                }

                Section("share_link.availability.label") {
                    Toggle("share_link.available_from.action", isOn: $editsAvailableDate)
                    if editsAvailableDate {
                        Toggle("common.label.available_from_date", isOn: $hasAvailableDate)
                        if hasAvailableDate {
                            DatePicker("common.column.available_date", selection: $availableDate)
                        }
                    }
                }

                Section("common.column.expiration") {
                    Toggle("share_link.expiration.action", isOn: $editsExpirationDate)
                    if editsExpirationDate {
                        Toggle("share_links.edit.has_expiration.label", isOn: $hasExpirationDate)
                        if hasExpirationDate {
                            DatePicker("common.column.expiration_date", selection: $expirationDate)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($focusError)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("share_links.edit.progress")
                }
                Button("common.button.save") { Task { await submit() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || !hasChanges)
            }
            .padding()
        }
        .frame(width: 560, height: 600)
        .onAppear {
            focusHeading = true
            VoiceOver.announce(String(localized: "files.share.edit.title"), category: .navigation)
        }
    }

    private var hasChanges: Bool {
        editsPassword || editsAvailableDate || editsExpirationDate
    }

    private func submit() async {
        let resultingAvailableDate = editsAvailableDate
            ? (hasAvailableDate ? availableDate : nil)
            : sharingDate(link.availableDate)
        let resultingExpirationDate = editsExpirationDate
            ? (hasExpirationDate ? expirationDate : nil)
            : sharingDate(link.expirationDate)
        if let resultingAvailableDate, let resultingExpirationDate,
           resultingAvailableDate > resultingExpirationDate {
            showError(
                String(localized: "common.validation.available_before_expiration")
            )
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let changes = FileStationShareLinkChanges(
            password: editsPassword ? password : nil,
            expirationDate: editsExpirationDate
                ? (hasExpirationDate ? sharingDateString(expirationDate) : "0")
                : nil,
            availableDate: editsAvailableDate
                ? (hasAvailableDate ? sharingDateString(availableDate) : "0")
                : nil
        )
        let outcome = await save(changes)
        switch outcome {
        case .success:
            VoiceOver.announce(outcome, priority: .high)
            dismiss()
        case .failure(let message):
            showError(message)
        case .cancelled:
            break
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        focusError = true
        VoiceOver.announce(message, category: .error, priority: .high)
    }
}

struct ShareLinkDetailsSheet: View {
    @Bindable var vm: FileBrowserViewModel
    let link: SharingLink

    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("share_links.detail.title")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            Divider()

            content

            Divider()

            HStack {
                Button("common.button.copy_link") { copy(details.url) }
                Spacer()
                Button("common.button.close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 580, height: 590)
        .task { await load() }
        .onDisappear { vm.clearShareLinkDetails() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingShareLinkDetails && vm.shareLinkDetails == nil {
            ModuleLoadingView("share_links.detail.loading")
        } else if let error = vm.shareLinkDetailsError {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.readableRed)
                    .multilineTextAlignment(.center)
                    .accessibilityFocused($focusError)
                Button("common.button.retry") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section("share_links.detail.link") {
                    LabeledContent("share_links.detail.url") {
                        Text(details.url)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    if let name = details.name { LabeledContent("common.column.name", value: name) }
                    if let path = details.path { LabeledContent("common.column.path", value: path) }
                    if let owner = details.owner { LabeledContent("common.column.owner", value: owner) }
                }

                Section("common.column.state") {
                    if let status = details.status { LabeledContent("common.column.status", value: status) }
                    if let hasPassword = details.hasPassword {
                        LabeledContent("common.label.password_protection") {
                            Text(
                                hasPassword
                                    ? String(localized: "common.status.enabled.feminine")
                                    : String(localized: "common.status.disabled.feminine")
                            )
                        }
                    }
                    if let isFolder = details.isFolder {
                        LabeledContent("common.column.kind") {
                            Text(
                                isFolder
                                    ? String(localized: "common.value.folder")
                                    : String(localized: "common.value.file")
                            )
                        }
                    }
                    if let availableDate = details.availableDate {
                        LabeledContent("share_link.available_from.label", value: availableDate)
                    }
                    if let expirationDate = details.expirationDate {
                        LabeledContent("share_links.detail.expires_on", value: expirationDate)
                    }
                    if let creationError = details.creationError, creationError != 0 {
                        LabeledContent("share_link.error.code.label") {
                            Text(creationError, format: .number.grouping(.never))
                        }
                    }
                }

                if let qrImage {
                    Section("share_links.detail.qr_code") {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .accessibilityLabel("share_links.detail.qr_code.label")
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var details: SharingLink { vm.shareLinkDetails ?? link }

    private var qrImage: NSImage? {
        guard let qrCode = details.qrCode else { return nil }
        let encoded = qrCode.split(separator: ",", maxSplits: 1).last.map(String.init) ?? qrCode
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return NSImage(data: data)
    }

    private func load() async {
        focusHeading = true
        VoiceOver.announce(
            String(localized: "share_links.detail.loading"),
            category: .progress,
            priority: .low
        )
        await vm.loadShareLinkDetails(link)
        guard !Task.isCancelled else { return }
        if let error = vm.shareLinkDetailsError {
            focusError = true
            VoiceOver.announce(error, category: .error, priority: .high)
        } else {
            focusHeading = true
            VoiceOver.announce(String(localized: "files.share.details.loaded.announcement"), category: .result)
        }
    }

    private func copy(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        VoiceOver.announce(String(localized: "common.status.link_copied"))
    }
}
