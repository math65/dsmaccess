//
//  ShareSheet.swift
//  dsmaccess
//
//  Feuille de création d'un lien de partage, en deux phases dans une seule feuille :
//  1. Options : mot de passe (facultatif) + expiration.
//  2. Résultat : l'URL, copiée automatiquement dans le presse-papier.
//  Accessible : focus + annonce à chaque phase.
//

import AppKit
import SwiftUI

struct ShareSheet: View {
    let item: FileStationItem
    let create: (_ password: String?, _ dateExpired: String?) async -> FileBrowserViewModel.ShareOutcome

    @State private var phase: Phase = .options
    @State private var password = ""
    @State private var expiry: Expiry = .never
    @State private var isCreating = false
    @State private var errorMessage: String?
    @FocusState private var passwordFocused: Bool
    @AccessibilityFocusState private var focusURL: Bool
    @AccessibilityFocusState private var focusError: Bool
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case options
        case created(String)
    }

    /// Durées d'expiration proposées (plus accessible qu'un sélecteur de date exacte).
    enum Expiry: Hashable, CaseIterable {
        case never, oneDay, sevenDays, thirtyDays
        var label: LocalizedStringKey {
            switch self {
            case .never: return "Jamais"
            case .oneDay: return "1 jour"
            case .sevenDays: return "7 jours"
            case .thirtyDays: return "30 jours"
            }
        }
        var days: Int? {
            switch self {
            case .never: return nil
            case .oneDay: return 1
            case .sevenDays: return 7
            case .thirtyDays: return 30
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .options: optionsView
            case .created(let url): resultView(url: url)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private var optionsView: some View {
        Text("Créer un lien de partage")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)

        LabeledField(label: "Mot de passe (facultatif)") {
            SecureField("Mot de passe (facultatif)", text: $password)
                .focused($passwordFocused)
                .help("Protéger le lien de partage par un mot de passe")
        }

        Picker("Expiration", selection: $expiry) {
            ForEach(Expiry.allCases, id: \.self) { option in
                Text(option.label).tag(option)
            }
        }
        .help("Choisir la date d’expiration du lien")

        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .accessibilityFocused($focusError)
        }

        if isCreating {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Opération en cours…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }

        HStack {
            Spacer()
            Button("Annuler", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)
                .help("Annuler la création du lien")
            Button("Créer le lien") { Task { await createLink() } }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
                .help("Créer le lien de partage")
        }
        .onAppear {
            passwordFocused = true
            VoiceOver.announce(
                String(localized: "Créer un lien de partage"),
                category: .navigation
            )
        }
    }

    @ViewBuilder
    private func resultView(url: String) -> some View {
        Text("Lien de partage")
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
            Button("Fermer", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .help("Fermer le lien de partage")
            Button("Copier le lien") { copyToClipboard(url) }
                .keyboardShortcut(.defaultAction)
                .help("Copier le lien de partage")
        }
        .onAppear {
            copyToClipboard(url, announce: false)
            focusURL = true
            VoiceOver.announce(
                String(localized: "Lien de partage créé et copié"),
                category: .result
            )
        }
    }

    private func createLink() async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        errorMessage = nil
        VoiceOver.announce(
            String(localized: "Opération en cours…"),
            category: .progress,
            priority: .low
        )
        switch await create(password.isEmpty ? nil : password, expiryDate(for: expiry)) {
        case .link(let url):
            phase = .created(url)
        case .failure(let message):
            errorMessage = message
            focusError = true
            VoiceOver.announce(message, category: .error, priority: .high)
        }
    }

    /// Convertit l'expiration choisie en date « AAAA-MM-JJ » (nil = jamais).
    private func expiryDate(for expiry: Expiry) -> String? {
        guard let days = expiry.days,
              let date = Calendar.current.date(byAdding: .day, value: days, to: .now) else { return nil }
        return date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private func copyToClipboard(_ url: String, announce: Bool = true) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        if announce { VoiceOver.announce(String(localized: "Lien copié")) }
    }
}
