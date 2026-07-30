//
//  LoginView.swift
//  dsmaccess
//
//  Direct or QuickConnect sign-in screen. Switches to the verification code entry if DSM
//  asks for it (needsOTP state).
//

import SwiftUI

struct LoginView: View {
    @State private var vm: ConnectionViewModel
    @AccessibilityFocusState private var focusError: Bool
    @AccessibilityFocusState private var focusRestoring: Bool
    @AccessibilityFocusState private var focusHost: Bool
    @FocusState private var connectionFieldFocused: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: ConnectionViewModel(session: session))
    }

    var body: some View {
        @Bindable var vm = vm
        Group {
            if vm.isRestoring {
                restoringView
            } else if vm.state == .needsOTP {
                OTPView(vm: vm)
            } else if vm.state == .needsPasswordChange {
                PasswordChangeView(vm: vm)
            } else if vm.state == .awaitingApproval {
                SecureSignInApprovalView(vm: vm)
            } else {
                credentialsForm(vm: vm)
            }
        }
        .task { await vm.startupIfNeeded() }
        .alert(
            "login.certificate.untrusted.title",
            isPresented: Binding(
                get: { vm.pendingCertificateFingerprint != nil },
                // The buttons carry the decision. SwiftUI also writes `false` while the
                // alert is dismissing, which must not turn an approval into a refusal
                // during the retried connection.
                set: { _ in }
            )
        ) {
            Button("common.button.cancel", role: .cancel) {
                vm.rejectPendingCertificate()
            }
            .help("login.certificate.reject.hint")
            Button("login.certificate.trust.button") {
                Task { await vm.approvePendingCertificate() }
            }
            .help("login.certificate.trust.hint")
        } message: {
            if let fingerprint = vm.pendingCertificateFingerprint {
                Text(String(localized: "login.certificate.untrusted.description", defaultValue: "DSM is using a certificate that macOS doesn't recognize. Verify this SHA-256 fingerprint before trusting it: \(fingerprint)"))
            }
        }
        .alert(
            "common.label.passwordless_sign_in",
            isPresented: Binding(
                get: { vm.secureSignInFailure != nil },
                set: { if !$0 { vm.secureSignInFailure = nil } }
            )
        ) {
            Button("common.button.ok", role: .cancel) { vm.secureSignInFailure = nil }
        } message: {
            if let failure = vm.secureSignInFailure {
                Text(verbatim: failure)
            }
        }
    }

    /// Full screen shown during the automatic reconnection at launch.
    private var restoringView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityLabel("login.reconnecting.title")
            Text(String(localized: "login.reconnecting.message", defaultValue: "Reconnecting to \(vm.connectionLabel)…"))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusRestoring)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .task {
            focusRestoring = true
            VoiceOver.announce(
                String(localized: "login.reconnecting.title"),
                category: .progress
            )
        }
    }

    @ViewBuilder
    private func credentialsForm(vm: ConnectionViewModel) -> some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("login.title")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("login.title")

                VStack(alignment: .leading, spacing: 12) {
                    Picker("login.connection_method.label", selection: $vm.connectionMethod) {
                        Text("login.method.direct_address").tag(ConnectionViewModel.ConnectionMethod.direct)
                        Text("QuickConnect").tag(ConnectionViewModel.ConnectionMethod.quickConnect)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("login.connection-method")
                    .help("login.connection_method.hint")

                    if vm.connectionMethod == .direct {
                        LabeledField(label: "login.address.label") {
                            TextField("192.168.1.10", text: $vm.host)
                                .textContentType(.URL)
                                .focused($connectionFieldFocused)
                                .accessibilityFocused($focusHost)
                                .accessibilityIdentifier("login.host")
                                .help("login.address.hint")
                        }
                        Toggle("login.https.label", isOn: $vm.useHTTPS)
                            .onChange(of: vm.useHTTPS) { _, _ in vm.syncDefaultPortIfNeeded() }
                            .accessibilityIdentifier("login.https")
                            .help("login.https.hint")
                        LabeledField(label: "login.port.label") {
                            TextField("5000", text: $vm.portText)
                                .accessibilityIdentifier("login.port")
                                .help("login.port.hint")
                        }
                        if let portError = vm.portValidationMessage {
                            Text(portError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("login.port-error")
                        }
                    } else {
                        LabeledField(label: "login.quickconnect.label") {
                            TextField("login.quickconnect.field.placeholder", text: $vm.quickConnectID)
                                .focused($connectionFieldFocused)
                                .accessibilityFocused($focusHost)
                                .accessibilityIdentifier("login.quickconnect-id")
                                .help("login.quickconnect.hint")
                        }
                        if let quickConnectError = vm.quickConnectValidationMessage {
                            Text(quickConnectError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("login.quickconnect-error")
                        }
                        Text("login.quickconnect.footer")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    LabeledField(label: "login.username.label") {
                        TextField("", text: $vm.account)
                            .textContentType(.username)
                            .accessibilityIdentifier("login.account")
                            .help("login.username.hint")
                    }
                    Picker("login.section.authentication", selection: $vm.authenticationMethod) {
                        Text("common.field.password").tag(ConnectionViewModel.AuthenticationMethod.password)
                        // The Synology service name first: it is the one the user sees in DSM
                        // and in the mobile app that will ask them to approve.
                        Text("login.method.secure_signin")
                            .tag(ConnectionViewModel.AuthenticationMethod.secureSignIn)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("login.authentication-method")
                    .help("login.auth_method.hint")

                    if vm.authenticationMethod == .password {
                        LabeledField(label: "common.field.password") {
                            SecureField("", text: $vm.password)
                                .textContentType(.password)
                                .accessibilityIdentifier("login.password")
                                .help("login.password.hint")
                        }
                    } else {
                        Text("login.secure_signin.description")
                            .font(.callout)
                            .foregroundStyle(.readableSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle("login.stay_signed_in.label", isOn: $vm.rememberPassword)
                        .accessibilityHint("login.stay_signed_in.hint")
                        .accessibilityIdentifier("login.remember-password")
                        .help("login.stay_signed_in.description")
                }
                .disabled(vm.state != .editing)

                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityFocused($focusError)
                }

                HStack(spacing: 12) {
                    if let progress = vm.progressMessage {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(Text(verbatim: progress))
                        Text(verbatim: progress)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Spacer()
                    Button("login.connect.button") {
                        Task { await vm.submit() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!vm.canSubmit)
                    .accessibilityIdentifier("login.submit")
                    .help(vm.authenticationMethod == .password
                          ? "login.connect.hint"
                          : "login.secure_signin.hint")
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .onChange(of: vm.state) { _, newValue in
            if newValue == .connecting || newValue == .resolvingQuickConnect,
               let progress = vm.progressMessage {
                VoiceOver.announce(
                    progress,
                    category: .progress
                )
            }
        }
        .onChange(of: vm.connectionMethod) { _, _ in
            connectionFieldFocused = true
            focusHost = true
        }
        .onChange(of: vm.errorMessage) { _, newValue in
            if let newValue {
                VoiceOver.announce(newValue, category: .error, priority: .high)
                focusError = true
            }
        }
        .task {
            if let error = vm.errorMessage {
                focusError = true
                VoiceOver.announce(error, category: .error, priority: .high)
            } else {
                connectionFieldFocused = true
                focusHost = true
            }
        }
    }
}
