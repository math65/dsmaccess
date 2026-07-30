//
//  ShareSheet.swift
//  dsmaccess
//
//  Création accessible d’un lien File Station avec disponibilité et expiration exactes.
//

import AppKit
import SwiftUI

struct ShareSheet: View {
    let item: FileStationItem
    let create: (
        _ password: String?,
        _ expirationDate: String?,
        _ availableDate: String?
    ) async -> FileBrowserViewModel.ShareOutcome

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.options
    @State private var password = ""
    @State private var hasAvailableDate = false
    @State private var availableDate = Date.now
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date.now.addingTimeInterval(604_800)
    @State private var isCreating = false
    @State private var errorMessage: String?
    @FocusState private var passwordFocused: Bool
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusURL: Bool
    @AccessibilityFocusState private var focusError: Bool

    private enum Phase: Equatable {
        case options
        case created(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .options:
                optionsView
            case .created(let url):
                resultView(url: url)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder
    private var optionsView: some View {
        Text("common.action.create_share_link")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($focusHeading)

        Text(item.name)
            .foregroundStyle(.secondary)

        LabeledField(label: "share_links.create.password.label") {
            SecureField("share_links.create.password.label", text: $password)
                .focused($passwordFocused)
                .help("share_links.create.password.hint")
        }

        GroupBox("share_links.create.availability_period") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("common.label.available_from_date", isOn: $hasAvailableDate)
                if hasAvailableDate {
                    DatePicker("common.column.available_date", selection: $availableDate)
                }
                Toggle("share_links.create.expiration.toggle", isOn: $hasExpirationDate)
                if hasExpirationDate {
                    DatePicker("common.column.expiration_date", selection: $expirationDate)
                }
            }
            .padding(.top, 4)
        }

        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityFocused($focusError)
        }

        if isCreating {
            ProgressView("share_links.create.progress")
        }

        HStack {
            Spacer()
            Button("common.button.cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)
                .help("share_links.create.cancel.button")
            Button("share_links.create.button") { Task { await createLink() } }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
                .help("share_links.create.button.label")
        }
        .onAppear {
            focusHeading = true
            passwordFocused = true
            VoiceOver.announce(String(localized: "common.action.create_share_link"), category: .navigation)
        }
    }

    @ViewBuilder
    private func resultView(url: String) -> some View {
        Text("share_links.create.title")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)

        Text(url)
            .textSelection(.enabled)
            .font(.body.monospaced())
            .lineLimit(3)
            .truncationMode(.middle)
            .accessibilityLabel(url)
            .accessibilityFocused($focusURL)

        HStack {
            Spacer()
            Button("common.button.close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .help("share_links.create.close.button")
            Button("common.button.copy_link") { copyToClipboard(url) }
                .keyboardShortcut(.defaultAction)
                .help("share_links.create.copy.button")
        }
        .onAppear {
            copyToClipboard(url, announce: false)
            focusURL = true
            VoiceOver.announce(
                String(localized: "share_links.create.success"),
                category: .result
            )
        }
    }

    private func createLink() async {
        guard !isCreating else { return }
        if hasAvailableDate, hasExpirationDate, availableDate > expirationDate {
            let message = String(
                localized: "common.validation.available_before_expiration"
            )
            errorMessage = message
            focusError = true
            VoiceOver.announce(message, category: .error, priority: .high)
            return
        }

        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        VoiceOver.announce(
            String(localized: "share_links.create.progress"),
            category: .progress,
            priority: .low
        )
        switch await create(
            password.isEmpty ? nil : password,
            hasExpirationDate ? sharingDateString(expirationDate) : nil,
            hasAvailableDate ? sharingDateString(availableDate) : nil
        ) {
        case .link(let url):
            phase = .created(url)
        case .failure(let message):
            errorMessage = message
            focusError = true
            VoiceOver.announce(message, category: .error, priority: .high)
        case .cancelled:
            break
        }
    }

    private func copyToClipboard(_ url: String, announce: Bool = true) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        if announce { VoiceOver.announce(String(localized: "common.status.link_copied")) }
    }
}

func sharingDateString(_ date: Date) -> String {
    date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
}

func sharingDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let style = Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)
    return try? Date(value, strategy: style.parseStrategy)
}
