//
//  NameEntrySheet.swift
//  dsmaccess
//
//  Feuille de saisie d'un nom, réutilisée pour « Créer un dossier » et « Renommer ».
//  Accessible : focus (clavier + VoiceOver) déposé sur le champ à l'ouverture, annonce du
//  titre, validation par Entrée. Première `.sheet` du projet.
//

import SwiftUI

struct NameEntrySheet: View {
    let title: LocalizedStringKey
    let fieldLabel: LocalizedStringKey
    let confirmLabel: LocalizedStringKey
    /// Message (déjà localisé) annoncé à VoiceOver à l'ouverture.
    let announcement: String
    let onConfirm: (String) -> Void

    @State private var name: String
    @FocusState private var fieldFocused: Bool
    @AccessibilityFocusState private var a11yFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: LocalizedStringKey,
         fieldLabel: LocalizedStringKey,
         confirmLabel: LocalizedStringKey,
         announcement: String,
         initialName: String = "",
         onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.fieldLabel = fieldLabel
        self.confirmLabel = confirmLabel
        self.announcement = announcement
        self.onConfirm = onConfirm
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LabeledField(label: fieldLabel) {
                TextField(fieldLabel, text: $name)
                    .focused($fieldFocused)
                    .accessibilityFocused($a11yFocused)
                    .onSubmit(confirm)
                    .help(fieldLabel)
            }

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("Annuler cette opération")
                Button(confirmLabel, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
                    .help(confirmLabel)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            fieldFocused = true
            a11yFocused = true
            VoiceOver.announce(announcement, category: .navigation)
        }
    }

    private func confirm() {
        let value = trimmedName
        guard !value.isEmpty else { return }
        onConfirm(value)
        dismiss()
    }
}
