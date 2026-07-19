//
//  LoginView.swift
//  dsmaccess
//
//  Écran de connexion : adresse du NAS, HTTPS, port, identifiants. Bascule vers la
//  saisie du code de vérification si DSM le réclame (état needsOTP).
//

import SwiftUI

struct LoginView: View {
    @State private var vm: ConnectionViewModel
    @AccessibilityFocusState private var focusError: Bool
    @AccessibilityFocusState private var focusRestoring: Bool
    @AccessibilityFocusState private var focusHost: Bool
    @FocusState private var hostFocused: Bool

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
    }

    /// Écran plein affiché pendant la reconnexion automatique au lancement.
    private var restoringView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityLabel("Reconnexion en cours")
            Text("Reconnexion à \(vm.host)…")
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
                    LabeledField(label: "Adresse du NAS (IP ou nom)") {
                        TextField("192.168.1.10", text: $vm.host)
                            .textContentType(.URL)
                            .focused($hostFocused)
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
                    LabeledField(label: "Nom d'utilisateur") {
                        TextField("", text: $vm.account)
                            .textContentType(.username)
                            .accessibilityIdentifier("login.account")
                            .help("Nom du compte DSM")
                    }
                    LabeledField(label: "Mot de passe") {
                        SecureField("", text: $vm.password)
                            .textContentType(.password)
                            .accessibilityIdentifier("login.password")
                            .help("Mot de passe du compte DSM")
                    }
                    Toggle("Rester connecté", isOn: $vm.rememberPassword)
                        .accessibilityHint("Mémorise le mot de passe pour la prochaine ouverture de l'app")
                        .accessibilityIdentifier("login.remember-password")
                        .help("Mémoriser le mot de passe dans le Trousseau pour les prochaines ouvertures")
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
                            .accessibilityLabel("Connexion en cours")
                        Text("Connexion en cours…")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    Spacer()
                    Button("Se connecter") {
                        Task { await vm.connect() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!vm.canSubmit)
                    .accessibilityIdentifier("login.submit")
                    .help("Se connecter au NAS avec les informations saisies")
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .onChange(of: vm.state) { _, newValue in
            if newValue == .connecting {
                VoiceOver.announce(
                    String(localized: "Connexion en cours"),
                    category: .progress
                )
            }
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
                hostFocused = true
                focusHost = true
            }
        }
    }
}
