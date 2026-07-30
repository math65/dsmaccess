//
//  SecureSignInApprovalView.swift
//  dsmaccess
//
//  Attente de l'approbation envoyée à l'app mobile Synology Secure SignIn. Le NAS ne
//  joint pas toujours un chiffre à confirmer : quand il le fait, c'est l'information
//  décisive de l'écran, annoncée en priorité.
//

import SwiftUI

struct SecureSignInApprovalView: View {
    @Bindable var vm: ConnectionViewModel
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("common.label.passwordless_sign_in")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            Text("secure_signin.approval.description")
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let verifyNumber = vm.secureSignInRequest?.verifyNumber {
                VStack(alignment: .leading, spacing: 4) {
                    Text("secure_signin.approval.number.label")
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)
                    Text(verifyNumber, format: .number)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(String(localized: "secure_signin.approval.number.value", defaultValue: "Number to confirm: \(verifyNumber)")))
                .accessibilityIdentifier("securesignin.verify-number")
            }

            if let error = vm.errorMessage {
                Text(error)
                    .foregroundStyle(.readableRed)
                    .accessibilityFocused($focusError)
            }

            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("secure_signin.approval.waiting.title")
                Text("secure_signin.approval.waiting.progress")
                    .foregroundStyle(.readableSecondary)
                    .accessibilityHidden(true)
                Spacer()
                Button("common.button.cancel") {
                    Task { await vm.cancelSecureSignIn() }
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("securesignin.cancel")
                .help("secure_signin.approval.cancel.hint")
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
        .onAppear {
            focusHeading = true
            VoiceOver.announce(announcement, category: .navigation, priority: .high)
        }
        // Le chiffre peut n'arriver qu'à la première interrogation du statut, après
        // l'affichage de l'écran : il doit alors être annoncé à son tour.
        .onChange(of: vm.secureSignInRequest?.verifyNumber) { previous, current in
            guard previous == nil, let current else { return }
            VoiceOver.announce(
                String(localized: "secure_signin.approval.number.value", defaultValue: "Number to confirm: \(current)"),
                category: .navigation,
                priority: .high
            )
        }
        .onChange(of: vm.errorMessage) { _, newValue in
            if let newValue {
                focusError = true
                VoiceOver.announce(newValue, category: .error, priority: .high)
            }
        }
    }

    private var announcement: String {
        guard let verifyNumber = vm.secureSignInRequest?.verifyNumber else {
            return String(localized: "secure_signin.approval.announcement")
        }
        return String(
            localized: "secure_signin.approval.number.announcement",
            defaultValue: "Approve the sign-in in the Synology Secure SignIn app. Number to confirm: \(verifyNumber)"
        )
    }
}
