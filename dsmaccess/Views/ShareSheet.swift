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
    /// Crée le lien et renvoie le résultat (injecté par la coquille).
    let create: (_ password: String?, _ dateExpired: String?) async -> FileBrowserViewModel.ShareOutcome

    @State private var phase: Phase = .options
    @State private var password = ""
    @State private var expiry: Expiry = .never
    @State private var isCreating = false
    @State private var errorMessage: String?
    @FocusState private var passwordFocused: Bool
    @AccessibilityFocusState private var focusURL: Bool
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
        }

        Picker("Expiration", selection: $expiry) {
            ForEach(Expiry.allCases, id: \.self) { option in
                Text(option.label).tag(option)
            }
        }

        if let errorMessage {
            Text(errorMessage).foregroundStyle(.red)
        }

        HStack {
            Spacer()
            Button("Annuler", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Créer le lien") { Task { await createLink() } }
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
        }
        .onAppear {
            passwordFocused = true
            VoiceOver.announce(String(localized: "Créer un lien de partage"))
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
            Button("Copier le lien") { copyToClipboard(url) }
                .keyboardShortcut(.defaultAction)
        }
        .onAppear {
            copyToClipboard(url, announce: false)
            focusURL = true
            VoiceOver.announce(String(localized: "Lien de partage créé et copié"))
        }
    }

    private func createLink() async {
        isCreating = true
        errorMessage = nil
        switch await create(password.isEmpty ? nil : password, expiryDate(for: expiry)) {
        case .link(let url):
            phase = .created(url)
        case .failure(let message):
            errorMessage = message
            VoiceOver.announce(message, priority: .high)
        }
        isCreating = false
    }

    /// Convertit l'expiration choisie en date « AAAA-MM-JJ » (nil = jamais).
    private func expiryDate(for expiry: Expiry) -> String? {
        guard let days = expiry.days,
              let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func copyToClipboard(_ url: String, announce: Bool = true) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        if announce { VoiceOver.announce(String(localized: "Lien copié")) }
    }
}
