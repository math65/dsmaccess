//
//  FeedbackView.swift
//  dsmaccess
//
//  Formulaire « Contacter le développeur » : signalement de problème (avec
//  instantané de diagnostic), suggestion ou question. Accessible dans tous les
//  états : focus posé à l'ouverture, envoi annoncé, erreur visible, annoncée et
//  focalisée, fermeture automatique après succès.
//

import SwiftUI

struct FeedbackView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var model = FeedbackViewModel()
    @FocusState private var typeFocused: Bool
    @AccessibilityFocusState private var typeA11yFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool

    var body: some View {
        Group {
            if AppBackendClient.isConfigured {
                form
            } else {
                unavailable
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Contacter le développeur")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Picker("Type de message", selection: $model.contactType) {
                ForEach(AppBackendClient.ContactType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .focused($typeFocused)
            .accessibilityFocused($typeA11yFocused)

            LabeledField(label: "Votre adresse e-mail (pour la réponse)") {
                TextField("Votre adresse e-mail (pour la réponse)", text: $model.email)
                    .textContentType(.emailAddress)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Message")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextEditor(text: $model.message)
                    .font(.body)
                    .frame(minHeight: 120)
                    .border(.separator)
                    .accessibilityLabel("Message")
            }

            if model.contactType == .bug {
                Text("Un instantané de diagnostic sera joint : versions de l’app et de macOS, langue et réglages. Aucune donnée de votre NAS n’est transmise.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityFocused($errorFocused)
            }

            HStack {
                if model.isSending {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Envoi du message en cours")
                }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Envoyer") {
                    Task {
                        await model.send(sessionConnected: session.isLoggedIn, settings: settings)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSend)
            }
        }
        .disabled(model.isSending)
        .onAppear {
            typeFocused = true
            typeA11yFocused = true
        }
        .onChange(of: model.errorMessage) { _, newValue in
            if newValue != nil {
                errorFocused = true
            }
        }
        .onChange(of: model.didSucceed) { _, didSucceed in
            if didSucceed {
                dismiss()
            }
        }
    }

    private var unavailable: some View {
        Text("L’envoi de messages n’est pas disponible dans cette version de l’app.")
            .frame(minHeight: 80)
    }
}
