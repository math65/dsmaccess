//
//  OTPView.swift
//  dsmaccess
//
//  Saisie du code de vérification à deux facteurs. Affiché uniquement quand DSM le
//  réclame. Le focus VoiceOver est placé sur le champ dès l'apparition.
//
//  Note : l'approbation « push » de l'app Synology n'est pas déclenchable par une app
//  tierce — d'où la saisie manuelle du code à 6 chiffres.
//

import SwiftUI

struct OTPView: View {
    @Bindable var vm: ConnectionViewModel
    @AccessibilityFocusState private var focusCode: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vérification en deux étapes")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Text("Ouvrez l'app Synology Secure SignIn et saisissez le code à 6 chiffres affiché.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "Code de vérification") {
                TextField("123456", text: $vm.otpCode)
                    .accessibilityFocused($focusCode)
                    .onSubmit { Task { await vm.submitOTP() } }
                    .help("Saisir le code de vérification à six chiffres")
            }

            Toggle("Se souvenir de cet appareil", isOn: $vm.rememberDevice)
                .help("Mémoriser ce Mac comme appareil approuvé")

            if let error = vm.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityFocused($focusError)
            }

            HStack(spacing: 12) {
                if vm.state == .connecting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Vérification en cours")
                    Text("Vérification en cours…")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer()
                Button("Annuler") { vm.cancelOTP() }
                    .help("Annuler la vérification et revenir à la connexion")
                Button("Valider") {
                    Task { await vm.submitOTP() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.otpCode.isEmpty || vm.state == .connecting)
                .help("Valider le code de vérification")
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
        .onAppear {
            focusCode = true
            VoiceOver.announce(
                String(localized: "Saisissez le code de vérification à six chiffres"),
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
