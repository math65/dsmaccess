//
//  LoginView.swift
//  dsmaccess
//
//  Écran de connexion directe ou QuickConnect. Bascule vers la saisie du code de
//  vérification si DSM le réclame (état needsOTP).
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
            "Certificat non approuvé",
            isPresented: Binding(
                get: { vm.pendingCertificateFingerprint != nil },
                // Les boutons portent la décision. SwiftUI écrit aussi `false` pendant
                // la fermeture de l'alerte, ce qui ne doit pas transformer une
                // approbation en refus pendant la nouvelle tentative de connexion.
                set: { _ in }
            )
        ) {
            Button("Annuler", role: .cancel) {
                vm.rejectPendingCertificate()
            }
            .help("Refuser le certificat et revenir à la connexion")
            Button("Approuver et se connecter") {
                Task { await vm.approvePendingCertificate() }
            }
            .help("Approuver ce certificat puis se connecter au NAS")
        } message: {
            if let fingerprint = vm.pendingCertificateFingerprint {
                Text("DSM utilise un certificat qui n'est pas reconnu par macOS. Vérifiez cette empreinte SHA-256 avant de l'approuver : \(fingerprint)")
            }
        }
        .alert(
            "Connexion sans mot de passe",
            isPresented: Binding(
                get: { vm.secureSignInFailure != nil },
                set: { if !$0 { vm.secureSignInFailure = nil } }
            )
        ) {
            Button("OK", role: .cancel) { vm.secureSignInFailure = nil }
        } message: {
            if let failure = vm.secureSignInFailure {
                Text(verbatim: failure)
            }
        }
    }

    /// Écran plein affiché pendant la reconnexion automatique au lancement.
    private var restoringView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityLabel("Reconnexion en cours")
            Text("Reconnexion à \(vm.connectionLabel)…")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusRestoring)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .task {
            focusRestoring = true
            VoiceOver.announce(
                String(localized: "Reconnexion en cours"),
                category: .progress
            )
        }
    }

    @ViewBuilder
    private func credentialsForm(vm: ConnectionViewModel) -> some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Connexion au NAS")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("login.title")

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Méthode de connexion", selection: $vm.connectionMethod) {
                        Text("Adresse directe").tag(ConnectionViewModel.ConnectionMethod.direct)
                        Text("QuickConnect").tag(ConnectionViewModel.ConnectionMethod.quickConnect)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("login.connection-method")
                    .help("Choisir comment rechercher le NAS")

                    if vm.connectionMethod == .direct {
                        LabeledField(label: "Adresse du NAS (IP ou nom)") {
                            TextField("192.168.1.10", text: $vm.host)
                                .textContentType(.URL)
                                .focused($connectionFieldFocused)
                                .accessibilityFocused($focusHost)
                                .accessibilityIdentifier("login.host")
                                .help("Adresse IP ou nom réseau du NAS")
                        }
                        Toggle("Utiliser HTTPS (connexion sécurisée)", isOn: $vm.useHTTPS)
                            .onChange(of: vm.useHTTPS) { _, _ in vm.syncDefaultPortIfNeeded() }
                            .accessibilityIdentifier("login.https")
                            .help("Utiliser une connexion HTTPS chiffrée")
                        LabeledField(label: "Port") {
                            TextField("5000", text: $vm.portText)
                                .accessibilityIdentifier("login.port")
                                .help("Port réseau utilisé par DSM")
                        }
                        if let portError = vm.portValidationMessage {
                            Text(portError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("login.port-error")
                        }
                    } else {
                        LabeledField(label: "Identifiant QuickConnect") {
                            TextField("MonNAS", text: $vm.quickConnectID)
                                .focused($connectionFieldFocused)
                                .accessibilityFocused($focusHost)
                                .accessibilityIdentifier("login.quickconnect-id")
                                .help("Identifiant QuickConnect configuré dans DSM")
                        }
                        if let quickConnectError = vm.quickConnectValidationMessage {
                            Text(quickConnectError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("login.quickconnect-error")
                        }
                        Text("Compatibilité non officielle : Synology peut modifier ce service sans préavis.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    LabeledField(label: "Nom d'utilisateur") {
                        TextField("", text: $vm.account)
                            .textContentType(.username)
                            .accessibilityIdentifier("login.account")
                            .help("Nom du compte DSM")
                    }
                    Picker("Authentification", selection: $vm.authenticationMethod) {
                        Text("Mot de passe").tag(ConnectionViewModel.AuthenticationMethod.password)
                        Text("Sans mot de passe").tag(ConnectionViewModel.AuthenticationMethod.secureSignIn)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("login.authentication-method")
                    .help("Choisir comment prouver votre identité auprès du NAS")

                    if vm.authenticationMethod == .password {
                        LabeledField(label: "Mot de passe") {
                            SecureField("", text: $vm.password)
                                .textContentType(.password)
                                .accessibilityIdentifier("login.password")
                                .help("Mot de passe du compte DSM")
                        }
                    } else {
                        Text("Une demande d'approbation sera envoyée à l'app Synology Secure SignIn de votre mobile.")
                            .font(.callout)
                            .foregroundStyle(.readableSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Toggle("Rester connecté", isOn: $vm.rememberPassword)
                        .accessibilityHint("Garde la session ouverte pour les prochaines ouvertures de l’app")
                        .accessibilityIdentifier("login.remember-password")
                        .help("Conserver la session dans le Trousseau pour rouvrir l’app sans se reconnecter")
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
                    Button("Se connecter") {
                        Task { await vm.submit() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!vm.canSubmit)
                    .accessibilityIdentifier("login.submit")
                    .help(vm.authenticationMethod == .password
                          ? "Se connecter au NAS avec les informations saisies"
                          : "Envoyer une demande d'approbation à l'app Synology Secure SignIn")
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
