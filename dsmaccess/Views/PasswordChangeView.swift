//
//  PasswordChangeView.swift
//  dsmaccess
//
//  New password required by DSM before opening the session (login returning 410), after a
//  reset by the administrator. VoiceOver focus is placed on the first field as soon as it
//  appears.
//
//  The strength rules the NAS applies are not known to the app: it is DSM that refuses a
//  non-compliant password, and its message is displayed as is.
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
            Text("password_change.title")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)

            Text("password_change.description")
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "common.field.new_password") {
                SecureField("common.field.new_password", text: $vm.newPassword)
                    .accessibilityFocused($focusNewPassword)
                    .help("password_change.new_field.hint")
            }

            LabeledField(label: "password_change.confirm_field.label") {
                SecureField("password_change.confirm_field.label", text: $vm.newPasswordConfirmation)
                    .onSubmit { Task { await vm.submitPasswordChange() } }
                    .help("password_change.confirm_field.hint")
            }

            if let error = vm.errorMessage {
                Text(error)
                    .foregroundStyle(.readableRed)
                    .accessibilityFocused($focusError)
            }

            HStack(spacing: 12) {
                if vm.state == .connecting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("password_change.progress.label")
                    Text("password_change.progress.announcement")
                        .foregroundStyle(.readableSecondary)
                        .accessibilityHidden(true)
                }
                Spacer()
                Button("common.button.cancel") { vm.cancelPasswordChange() }
                    .help("password_change.cancel.hint")
                Button("password_change.submit.button") {
                    Task { await vm.submitPasswordChange() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .help("password_change.submit.hint")
            }
        }
        .padding(28)
        .frame(maxWidth: 460)
        .onAppear {
            focusNewPassword = true
            VoiceOver.announce(
                String(localized: "common.error.password_change_required"),
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
