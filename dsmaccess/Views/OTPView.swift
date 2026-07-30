//
//  OTPView.swift
//  dsmaccess
//
//  Saisie du code de vérification à deux facteurs. Affiché uniquement quand DSM le
//  réclame après une connexion par mot de passe. Le focus VoiceOver est placé sur le
//  champ dès l'apparition.
//
//  L'approbation « push » de Secure SignIn suit un autre chemin, sans mot de passe :
//  voir SecureSignInApprovalView.
//

import SwiftUI

struct OTPView: View {
    @Bindable var vm: ConnectionViewModel
    @AccessibilityFocusState private var focusCode: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("otp.title")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Text("otp.code.description")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "otp.code.label") {
                TextField("123456", text: $vm.otpCode)
                    .accessibilityFocused($focusCode)
                    .onSubmit { Task { await vm.submitOTP() } }
                    .help("otp.code.field.label")
            }

            Toggle("otp.remember_device", isOn: $vm.rememberDevice)
                .help("otp.remember_device.hint")

            if let error = vm.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .accessibilityFocused($focusError)
            }

            HStack(spacing: 12) {
                if vm.state == .connecting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("otp.verifying.label")
                    Text("otp.verifying.progress")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer()
                Button("common.button.cancel") { vm.cancelOTP() }
                    .help("otp.cancel.hint")
                Button("otp.submit.button") {
                    Task { await vm.submitOTP() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.otpCode.isEmpty || vm.state == .connecting)
                .help("otp.submit.hint")
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
        .onAppear {
            focusCode = true
            VoiceOver.announce(
                String(localized: "otp.code.field.placeholder"),
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
