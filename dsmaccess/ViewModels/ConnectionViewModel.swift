//
//  ConnectionViewModel.swift
//  dsmaccess
//
//  Machine à états de la connexion : saisie → tentative → (code 2FA si demandé) → connecté.
//  L'écran de code n'apparaît QUE si DSM renvoie « code requis » (erreur 403).
//

import Foundation
import Observation

@MainActor
@Observable
final class ConnectionViewModel {
    enum State: Equatable {
        case editing      // saisie des identifiants
        case connecting   // tentative en cours
        case needsOTP     // DSM réclame un code de vérification
    }

    // Champs du formulaire (pré-remplis depuis les préférences si disponibles).
    var host: String
    var useHTTPS: Bool
    var portText: String
    var account: String
    var password: String = ""
    var otpCode: String = ""
    var rememberDevice: Bool = true
    /// « Rester connecté » : mémoriser le mot de passe pour la reconnexion automatique.
    var rememberPassword: Bool

    private(set) var state: State = .editing
    /// Reconnexion automatique en cours au lancement (masque le formulaire).
    private(set) var isRestoring: Bool
    /// Message d'erreur à afficher et à annoncer (nil si aucun).
    var errorMessage: String?
    /// Empreinte d'un certificat non approuvé, en attente d'une décision explicite.
    private(set) var pendingCertificateFingerprint: String?
    /// Dernière erreur typée (sert à décider d'oublier un mot de passe mémorisé périmé).
    private var lastError: DSMError?
    /// Empêche de relancer la reconnexion automatique plus d'une fois.
    private var hasRunStartup = false

    private let session: SessionStore
    private var client: DSMClient?
    private var pendingEndpoint: DSMEndpoint?

    init(session: SessionStore) {
        self.session = session
        let https = Preferences.lastUseHTTPS
        let host = Preferences.lastHost
        let account = Preferences.lastAccount
        let effectivePort = Preferences.lastPort ?? DSMEndpoint.defaultPort(useHTTPS: https)
        self.host = host
        self.account = account
        self.useHTTPS = https
        self.portText = String(effectivePort)
        self.rememberPassword = Preferences.rememberPassword
        self.errorMessage = session.consumeDisconnectionMessage()
        // Reconnexion possible au lancement si un mot de passe est mémorisé pour ce NAS.
        if Preferences.rememberPassword, !host.isEmpty, !account.isEmpty {
            let endpoint = DSMEndpoint(useHTTPS: https, host: host, port: effectivePort)
            self.isRestoring = CredentialStore.password(account: account, endpoint: endpoint) != nil
        } else {
            self.isRestoring = false
        }
    }

    /// Port validé. Une saisie non numérique ou hors plage n'est jamais remplacée en silence.
    var port: Int? {
        guard let value = Int(portText), (1...65_535).contains(value) else { return nil }
        return value
    }

    var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !account.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && port != nil
            && state != .connecting
    }

    /// Ajuste le port par défaut quand on bascule HTTP/HTTPS, si l'utilisateur n'a pas
    /// saisi un port personnalisé.
    func syncDefaultPortIfNeeded() {
        let httpDefault = String(DSMEndpoint.defaultPort(useHTTPS: false))
        let httpsDefault = String(DSMEndpoint.defaultPort(useHTTPS: true))
        if portText == httpDefault || portText == httpsDefault || portText.isEmpty {
            portText = String(DSMEndpoint.defaultPort(useHTTPS: useHTTPS))
        }
    }

    // MARK: - Actions

    /// Première tentative : identifiants seuls (+ jeton d'appareil mémorisé si présent).
    func connect() async {
        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        let cleanedAccount = account.trimmingCharacters(in: .whitespaces)
        guard !cleanedHost.isEmpty, !cleanedAccount.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "Veuillez renseigner l'adresse, le nom d'utilisateur et le mot de passe.")
            return
        }

        guard let port else {
            errorMessage = String(localized: "Le port doit être un nombre compris entre 1 et 65535.")
            return
        }
        let endpoint = DSMEndpoint(useHTTPS: useHTTPS, host: cleanedHost, port: port)
        let client = DSMClient(endpoint: endpoint)
        self.client = client
        self.pendingEndpoint = endpoint

        state = .connecting
        errorMessage = nil
        lastError = nil

        let deviceID = KeychainStore.load(service: KeychainStore.deviceTokenService, account: keychainKey(cleanedAccount, endpoint))

        do {
            let result = try await client.login(
                account: cleanedAccount, password: password,
                otpCode: nil, deviceID: deviceID, rememberDevice: false
            )
            try await finish(with: result, account: cleanedAccount, endpoint: endpoint)
        } catch DSMError.needsOTP {
            state = .needsOTP
            errorMessage = nil
        } catch DSMError.untrustedCertificate(let fingerprint) {
            state = .editing
            pendingCertificateFingerprint = fingerprint
            errorMessage = nil
        } catch {
            state = .editing
            lastError = error as? DSMError
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Reconnexion automatique au lancement, si un mot de passe est mémorisé pour ce NAS.
    /// Réutilise `connect()` ; si le mot de passe est refusé (périmé), on l'oublie pour
    /// ne pas retenter en boucle au prochain lancement.
    func startupIfNeeded() async {
        guard isRestoring, !hasRunStartup else { return }
        hasRunStartup = true

        let cleanedHost = host.trimmingCharacters(in: .whitespaces)
        let cleanedAccount = account.trimmingCharacters(in: .whitespaces)
        guard let port else {
            isRestoring = false
            errorMessage = String(localized: "Le port doit être un nombre compris entre 1 et 65535.")
            return
        }
        let endpoint = DSMEndpoint(useHTTPS: useHTTPS, host: cleanedHost, port: port)
        guard let saved = CredentialStore.password(account: cleanedAccount, endpoint: endpoint) else {
            isRestoring = false
            return
        }

        password = saved
        await connect()
        isRestoring = false

        if !session.isLoggedIn, lastError?.isCredentialFailure == true {
            CredentialStore.forget(account: cleanedAccount, endpoint: endpoint)
            rememberPassword = false
            password = ""
        }
    }

    /// Soumission du code de vérification après un 403.
    func submitOTP() async {
        guard let client, let endpoint = pendingEndpoint else { return }
        let cleanedAccount = account.trimmingCharacters(in: .whitespaces)
        guard !otpCode.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = String(localized: "Saisissez le code de vérification.")
            return
        }

        state = .connecting
        errorMessage = nil

        do {
            let result = try await client.login(
                account: cleanedAccount, password: password,
                otpCode: otpCode.trimmingCharacters(in: .whitespaces),
                deviceID: nil, rememberDevice: rememberDevice
            )
            try await finish(with: result, account: cleanedAccount, endpoint: endpoint)
        } catch DSMError.badOTP {
            state = .needsOTP
            otpCode = ""
            errorMessage = DSMError.badOTP.errorDescription
        } catch DSMError.untrustedCertificate(let fingerprint) {
            state = .needsOTP
            pendingCertificateFingerprint = fingerprint
            errorMessage = nil
        } catch {
            state = .needsOTP
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Annule la saisie du code et revient au formulaire d'identifiants.
    func cancelOTP() {
        state = .editing
        otpCode = ""
        errorMessage = nil
    }

    func approvePendingCertificate() async {
        guard let fingerprint = pendingCertificateFingerprint,
              let endpoint = pendingEndpoint else { return }
        guard KeychainStore.save(
            fingerprint,
            service: KeychainStore.serverTrustService,
            account: endpoint.trustStoreKey
        ) else {
            pendingCertificateFingerprint = nil
            errorMessage = String(localized: "Le certificat n'a pas pu être enregistré dans le trousseau.")
            return
        }
        pendingCertificateFingerprint = nil
        client = nil
        await connect()
    }

    func rejectPendingCertificate() {
        pendingCertificateFingerprint = nil
        client = nil
        pendingEndpoint = nil
        state = .editing
    }

    // MARK: - Interne

    private func finish(with result: LoginResult, account: String, endpoint: DSMEndpoint) async throws {
        guard let client else { return }
        let capabilities: DSMCapabilities
        do {
            capabilities = try await client.discoverCapabilities()
        } catch {
            try? await client.logout()
            throw error
        }
        if rememberDevice, let did = result.did, !did.isEmpty {
            KeychainStore.save(did, service: KeychainStore.deviceTokenService, account: keychainKey(account, endpoint))
        }
        // Mémoriser (ou oublier) le mot de passe selon le choix « Rester connecté ».
        if rememberPassword {
            CredentialStore.remember(password: password, account: account, endpoint: endpoint)
        } else {
            CredentialStore.forget(account: account, endpoint: endpoint)
        }
        persistPreferences(account: account, endpoint: endpoint)
        session.establish(
            endpoint: endpoint,
            client: client,
            capabilities: capabilities
        )
        // RootView bascule automatiquement vers l'écran de contenu.
        state = .editing
        errorMessage = nil
        lastError = nil
        password = ""
        otpCode = ""
    }

    private func keychainKey(_ account: String, _ endpoint: DSMEndpoint) -> String {
        "\(account)@\(endpoint.host):\(endpoint.port)"
    }

    private func persistPreferences(account: String, endpoint: DSMEndpoint) {
        Preferences.lastHost = endpoint.host
        Preferences.lastPort = endpoint.port
        Preferences.lastUseHTTPS = endpoint.useHTTPS
        Preferences.lastAccount = account
    }
}
