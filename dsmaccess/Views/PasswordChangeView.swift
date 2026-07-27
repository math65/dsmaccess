//
//  PasswordChangeView.swift
//  dsmaccess
//
//  Nouveau mot de passe exigé par DSM avant l'ouverture de session (login en 410),
//  après une réinitialisation par l'administrateur. Le focus VoiceOver est placé sur
//  le premier champ dès l'apparition.
//
//  Les règles de force appliquées par le NAS ne sont pas connues de l'app : c'est DSM
//  qui refuse un mot de passe non conforme, et son message est affiché tel quel.
//

import SwiftUI

struct PasswordChangeView: View {
    @Bindable var vm: ConnectionViewModel
    @AccessibilityFocusState private var focusNewPassword: Bool
    @AccessibilityFocusState private var focusError: Bool

    private var canSubmit: Bool {
        !vm.newPassword.isEmpty
            && !vm.newPasswordConfirmation.isEmpty
            && vm.state != .connecting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nouveau mot de passe requis")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Text("DSM demande de changer le mot de passe de ce compte avant de se connecter.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "Nouveau mot de passe") {
                SecureField("Nouveau mot de passe", text: $vm.newPassword)
                    .accessibilityFocused($focusNewPassword)
                    .help("Saisir le nouveau mot de passe du compte")
            }

            LabeledField(label: "Confirmer le nouveau mot de passe") {
                SecureField("Confirmer le nouveau mot de passe", text: $vm.newPasswordConfirmation)
                    .onSubmit { Task { await vm.submitPasswordChange() } }
                    .help("Saisir à nouveau le mot de passe pour confirmation")
            }

            if let error = vm.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityFocused($focusError)
            }

            HStack(spacing: 12) {
                if vm.state == .connecting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Changement du mot de passe en cours")
                    Text("Changement du mot de passe en cours…")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer()
                Button("Annuler") { vm.cancelPasswordChange() }
                    .help("Renoncer au changement et revenir à la connexion")
                Button("Changer le mot de passe") {
                    Task { await vm.submitPasswordChange() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .help("Enregistrer le nouveau mot de passe puis se connecter")
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
        .onAppear {
            focusNewPassword = true
            VoiceOver.announce(
                String(localized: "Ce compte doit changer son mot de passe avant de se connecter."),
                category: .navigation
            )
        }
        .onChange(of: vm.errorMessage) { _, newValue in
            if let newValue {
                focusError = true
                VoiceOver.announce(newValue, category: .error, priority: .high)
            }
        }
    }
}
