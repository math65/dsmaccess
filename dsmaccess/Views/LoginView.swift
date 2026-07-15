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
                set: { if !$0 { vm.rejectPendingCertificate() } }
            )
        ) {
            Button("Annuler", role: .cancel) {
                vm.rejectPendingCertificate()
            }
            Button("Approuver et se connecter") {
                Task { await vm.approvePendingCertificate() }
            }
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
            Text("Reconnexion à \(vm.host)…")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusRestoring)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .task {
            focusRestoring = true
            VoiceOver.announce(String(localized: "Reconnexion en cours"))
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

                VStack(alignment: .leading, spacing: 12) {
                    LabeledField(label: "Adresse du NAS (IP ou nom)") {
                        TextField("192.168.1.10", text: $vm.host)
                            .textContentType(.URL)
                    }
                    Toggle("Utiliser HTTPS (connexion sécurisée)", isOn: $vm.useHTTPS)
                        .onChange(of: vm.useHTTPS) { _, _ in vm.syncDefaultPortIfNeeded() }
                    LabeledField(label: "Port") {
                        TextField("5000", text: $vm.portText)
                    }
                    LabeledField(label: "Nom d'utilisateur") {
                        TextField("", text: $vm.account)
                            .textContentType(.username)
                    }
                    LabeledField(label: "Mot de passe") {
                        SecureField("", text: $vm.password)
                            .textContentType(.password)
                    }
                    Toggle("Rester connecté", isOn: $vm.rememberPassword)
                        .accessibilityHint("Mémorise le mot de passe pour la prochaine ouverture de l'app")
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
                        Text("Connexion en cours…")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Se connecter") {
                        Task { await vm.connect() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!vm.canSubmit)
                }
            }
            .padding(28)
            .frame(maxWidth: 460)
        }
        .onChange(of: vm.state) { _, newValue in
            if newValue == .connecting {
                AccessibilityNotification.Announcement(String(localized: "Connexion en cours")).post()
            }
        }
        .onChange(of: vm.errorMessage) { _, newValue in
            if let newValue {
                AccessibilityNotification.Announcement(newValue).post()
                focusError = true
            }
        }
        .task {
            if let error = vm.errorMessage {
                focusError = true
                VoiceOver.announce(error)
            }
        }
    }
}
