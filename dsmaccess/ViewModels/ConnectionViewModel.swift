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
    enum ConnectionMethod: Hashable {
        case direct
        case quickConnect
    }

    /// Comment le compte prouve son identité. Le choix conditionne le formulaire : la
    /// connexion approuvée sur le mobile ne demande aucun mot de passe.
    enum AuthenticationMethod: Hashable {
        case password
        case secureSignIn
    }

    enum State: Equatable {
        case editing      // saisie des identifiants
        case resolvingQuickConnect
        case connecting   // tentative en cours
        case needsOTP     // DSM réclame un code de vérification
        case needsPasswordChange // DSM exige un nouveau mot de passe avant d'ouvrir la session
        case awaitingApproval    // connexion sans mot de passe : décision attendue sur le mobile
    }

    // Champs du formulaire (pré-remplis depuis les préférences si disponibles).
    var connectionMethod: ConnectionMethod
    var authenticationMethod: AuthenticationMethod = .password
    var host: String
    var quickConnectID: String
    var useHTTPS: Bool
    var portText: String
    var account: String
    var password: String = ""
    var otpCode: String = ""
    var newPassword: String = ""
    var newPasswordConfirmation: String = ""
    var rememberDevice: Bool = true
    /// « Rester connecté » : mémoriser le mot de passe pour la reconnexion automatique.
    var rememberPassword: Bool

    private(set) var state: State = .editing
    /// Demande d'approbation en cours ; porte le chiffre à confirmer quand le NAS en joint un.
    private(set) var secureSignInRequest: SecureSignInRequest?
    /// Issue d'une demande d'approbation qui n'a pas abouti, présentée en alerte.
    var secureSignInFailure: String?
    private var approvalTask: Task<Void, Never>?
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
    /// Non nul quand cet écran de connexion fait suite à une expiration de session :
    /// si la reconnexion automatique aboutit, l'interface connectée doit le signaler.
    private let expiredSessionMessage: String?

    private let session: SessionStore
    private let quickConnectResolver: QuickConnectResolver
    private var client: DSMClient?
    private var pendingEndpoint: DSMEndpoint?
    private var pendingTarget: NASConnectionTarget?

    init(
        session: SessionStore,
        quickConnectResolver: QuickConnectResolver = QuickConnectResolver()
    ) {
        self.session = session
        self.quickConnectResolver = quickConnectResolver
        let profile = session.connectionProfile
        let savedTarget = profile?.connection
        let directEndpoint = savedTarget?.directEndpoint
        let https = directEndpoint?.useHTTPS ?? Preferences.lastUseHTTPS
        let host = directEndpoint?.host ?? Preferences.lastHost
        let account = profile?.account ?? Preferences.lastAccount
        let effectivePort = directEndpoint?.port
            ?? Preferences.lastPort
            ?? DSMEndpoint.defaultPort(useHTTPS: https)
        if case .quickConnect(let id) = savedTarget {
            self.connectionMethod = .quickConnect
            self.quickConnectID = id
        } else {
            self.connectionMethod = .direct
            self.quickConnectID = ""
        }
        self.host = host
        self.account = account
        self.useHTTPS = https
        self.portText = String(effectivePort)
        self.rememberPassword = profile?.remembersPassword ?? Preferences.rememberPassword
        let disconnectionMessage = session.consumeDisconnectionMessage()
        self.expiredSessionMessage = disconnectionMessage
        self.errorMessage = disconnectionMessage
        // Reprise possible au lancement : une session mémorisée d'abord, à défaut un mot
        // de passe. La session ne dépend pas de `rememberPassword`, une connexion sans mot
        // de passe n'en enregistrant aucun.
        if !account.isEmpty,
           !Self.isRunningHostedTests,
           let target = savedTarget ?? Self.directTarget(
               host: host,
               useHTTPS: https,
               port: effectivePort
           ) {
            let hasSession = CredentialStore.session(account: account, target: target) != nil
            let hasPassword = Preferences.rememberPassword
                && CredentialStore.password(account: account, target: target) != nil
            self.isRestoring = hasSession || hasPassword
        } else {
            self.isRestoring = false
        }
    }

    // Les tests unitaires hébergés par l'app ne doivent toucher ni au Trousseau ni au NAS :
    // la lecture du Trousseau déclenche l'invite système et suspend le lanceur de tests.
    private static var isRunningHostedTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["DSM_ACCESS_BACKGROUND_TESTS"] == "YES"
            || environment["XCTestConfigurationFilePath"] != nil
    }

    /// Port validé. Une saisie non numérique ou hors plage n'est jamais remplacée en silence.
    var port: Int? {
        guard let value = Int(portText), (1...65_535).contains(value) else { return nil }
        return value
    }

    var canSubmit: Bool {
        connectionTarget != nil
            && !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state == .editing
            // La connexion approuvée sur le mobile ne demande que le nom d'utilisateur.
            && (authenticationMethod == .secureSignIn || !password.isEmpty)
    }

    /// Aiguillage du bouton unique de connexion.
    func submit() async {
        switch authenticationMethod {
        case .password: await connect()
        case .secureSignIn: startSecureSignIn()
        }
    }

    var portValidationMessage: String? {
        guard connectionMethod == .direct else { return nil }
        guard port == nil else { return nil }
        return String(localized: "Le port doit être un nombre compris entre 1 et 65535.")
    }

    var quickConnectValidationMessage: String? {
        guard connectionMethod == .quickConnect else { return nil }
        let id = quickConnectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !QuickConnectResolver.isValid(id: id) else { return nil }
        return String(localized: "L’identifiant QuickConnect n’est pas valide.")
    }

    var connectionLabel: String {
        switch connectionMethod {
        case .direct:
            host.trimmingCharacters(in: .whitespacesAndNewlines)
        case .quickConnect:
            quickConnectID.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var progressMessage: String? {
        switch state {
        case .resolvingQuickConnect:
            String(localized: "Recherche du NAS avec QuickConnect…")
        case .connecting:
            String(localized: "Connexion en cours…")
        case .editing, .needsOTP, .needsPasswordChange, .awaitingApproval:
            nil
        }
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
        await connect(reusingPendingClient: false)
    }

    private func connect(reusingPendingClient: Bool) async {
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAccount.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "Veuillez renseigner le nom d’utilisateur et le mot de passe.")
            return
        }

        guard let target = connectionTarget else {
            errorMessage = connectionValidationMessage
            return
        }

        state = connectionMethod == .quickConnect && !reusingPendingClient
            ? .resolvingQuickConnect
            : .connecting
        errorMessage = nil
        lastError = nil

        do {
            let endpoint: DSMEndpoint
            let activeClient: DSMClient
            if reusingPendingClient,
               pendingTarget == target,
               let pendingEndpoint,
               let client {
                endpoint = pendingEndpoint
                activeClient = client
            } else {
                endpoint = try await resolvedEndpoint(for: target)
                try Task.checkCancellation()
                activeClient = DSMClient(endpoint: endpoint)
                client = activeClient
                pendingEndpoint = endpoint
                pendingTarget = target
            }
            state = .connecting
            let deviceID = CredentialStore.deviceID(account: cleanedAccount, target: target)
            let result = try await activeClient.login(
                account: cleanedAccount, password: password,
                otpCode: nil, deviceID: deviceID, rememberDevice: false
            )
            try await finish(
                with: result,
                account: cleanedAccount,
                target: target,
                endpoint: endpoint
            )
        } catch DSMError.needsOTP {
            state = .needsOTP
            errorMessage = nil
        } catch DSMError.passwordMustChange {
            state = .needsPasswordChange
            errorMessage = nil
        } catch DSMError.untrustedCertificate(let fingerprint) {
            state = .editing
            pendingCertificateFingerprint = fingerprint
            errorMessage = nil
        } catch where DSMError.isCancellation(error) {
            state = .editing
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

        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = connectionTarget else {
            isRestoring = false
            errorMessage = connectionValidationMessage
            return
        }
        if await resumeStoredSession(account: cleanedAccount, target: target) {
            isRestoring = false
            if expiredSessionMessage != nil {
                session.publishAutomaticReconnectionNotice()
            }
            return
        }

        guard let saved = CredentialStore.password(account: cleanedAccount, target: target) else {
            isRestoring = false
            return
        }

        for attempt in 0..<3 {
            password = saved
            if connectionMethod == .quickConnect, pendingTarget == target {
                await connect(reusingPendingClient: true)
            } else {
                await connect()
            }
            if session.isLoggedIn || !hasTransientNetworkFailure || attempt == 2 {
                break
            }
            errorMessage = nil
            do {
                try await Task.sleep(for: .milliseconds(750 * (attempt + 1)))
            } catch {
                isRestoring = false
                return
            }
        }
        isRestoring = false
        if session.isLoggedIn, expiredSessionMessage != nil {
            session.publishAutomaticReconnectionNotice()
        }

        if !session.isLoggedIn, lastError?.isCredentialFailure == true {
            CredentialStore.forget(account: cleanedAccount, target: target)
            rememberPassword = false
            password = ""
        }
    }

    /// Rouvre la session mémorisée sans rien redemander à l'utilisateur. Vrai si elle est
    /// encore valide et que l'app est entrée.
    ///
    /// La découverte des API ne prouve rien : `SYNO.API.Info` répond sans session. Il faut
    /// un appel authentifié — d'où la sonde — sinon une session morte passerait pour bonne
    /// jusqu'à la première vraie opération, qui échouerait sans explication.
    private func resumeStoredSession(
        account: String,
        target: NASConnectionTarget
    ) async -> Bool {
        guard let stored = CredentialStore.session(account: account, target: target) else {
            return false
        }
        do {
            let endpoint = try await resolvedEndpoint(for: target)
            try Task.checkCancellation()
            let activeClient = DSMClient(endpoint: endpoint)
            client = activeClient
            pendingEndpoint = endpoint
            pendingTarget = target
            activeClient.adoptSession(stored)
            let capabilities = try await activeClient.discoverCapabilities()
            _ = try await activeClient.systemInfo()
            enterSession(
                account: account,
                target: target,
                endpoint: endpoint,
                capabilities: capabilities,
                remembersPassword: CredentialStore.password(
                    account: account,
                    target: target
                ) != nil
            )
            return true
        } catch DSMError.sessionExpired {
            // Seul cas où la session est réellement en cause : ne pas la réessayer au
            // prochain lancement, et laisser le chemin habituel reprendre la main.
            CredentialStore.forgetSession(account: account, target: target)
            client = nil
            errorMessage = String(
                localized: "La session enregistrée n’est plus valide. Connectez-vous à nouveau."
            )
            return false
        } catch let error as DSMError where error.provesSessionIsAlive {
            // Le NAS nous a authentifiés puis refusé cette API : la session est bonne,
            // c'est le compte qui n'a pas le droit d'y accéder.
            let capabilities = client?.capabilities ?? DSMCapabilities()
            guard let endpoint = pendingEndpoint else { return false }
            enterSession(
                account: account,
                target: target,
                endpoint: endpoint,
                capabilities: capabilities,
                remembersPassword: CredentialStore.password(
                    account: account,
                    target: target
                ) != nil
            )
            return true
        } catch {
            // Réseau injoignable, certificat refusé : la session mémorisée n'est pas en
            // cause et doit survivre. Le chemin habituel affichera l'incident.
            client = nil
            return false
        }
    }

    /// Connexion sans mot de passe : le NAS envoie une demande d'approbation à l'app
    /// mobile Synology, puis l'app attend la décision. Aucun mot de passe n'est saisi ni
    /// transmis, ce qui en fait souvent le chemin le plus praticable avec VoiceOver.
    func startSecureSignIn() {
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAccount.isEmpty else {
            errorMessage = String(localized: "Veuillez renseigner le nom d’utilisateur.")
            return
        }
        guard let target = connectionTarget else {
            errorMessage = connectionValidationMessage
            return
        }
        // Une demande laissée en suspens par une tentative précédente doit être révoquée
        // avant d'en ouvrir une autre, sinon elle reste approuvable sur le téléphone. La
        // révocation part depuis la nouvelle tâche : lancée depuis l'ancienne, qu'on vient
        // d'annuler, la requête serait interrompue avant d'atteindre le NAS.
        let abandoned = secureSignInRequest
        approvalTask?.cancel()
        approvalTask = Task {
            if let abandoned {
                await client?.revokeSecureSignIn(
                    account: cleanedAccount,
                    requestID: abandoned.requestID
                )
            }
            await runSecureSignIn(account: cleanedAccount, target: target)
        }
    }

    /// Abandon demandé par l'utilisateur : la demande est révoquée sur le NAS pour ne pas
    /// laisser une approbation valable derrière soi.
    func cancelSecureSignIn() async {
        approvalTask?.cancel()
        approvalTask = nil
        await revokePendingSecureSignIn()
        secureSignInRequest = nil
        state = .editing
        errorMessage = nil
    }

    private func runSecureSignIn(account: String, target: NASConnectionTarget) async {
        state = connectionMethod == .quickConnect ? .resolvingQuickConnect : .connecting
        errorMessage = nil
        lastError = nil
        secureSignInRequest = nil

        do {
            let endpoint = try await resolvedEndpoint(for: target)
            try Task.checkCancellation()
            let activeClient = DSMClient(endpoint: endpoint)
            client = activeClient
            pendingEndpoint = endpoint
            pendingTarget = target

            _ = try? await activeClient.apiInfo(for: ["SYNO.SecureSignIn.Authenticator.Request"])
            guard activeClient.supportsSecureSignIn else {
                state = .editing
                errorMessage = String(
                    localized: "Ce NAS ne propose pas la connexion sans mot de passe."
                )
                return
            }

            let request = try await activeClient.requestSecureSignIn(
                account: account,
                rememberDevice: rememberDevice
            )
            try Task.checkCancellation()
            secureSignInRequest = request
            state = .awaitingApproval

            let token = try await awaitApproval(client: activeClient, account: account, request: request)
            let result = try await activeClient.completeSecureSignIn(
                account: account,
                requestID: request.requestID,
                token: token,
                rememberDevice: rememberDevice
            )
            try await finish(
                with: result,
                account: account,
                target: target,
                endpoint: endpoint,
                storesPassword: false
            )
            secureSignInRequest = nil
        } catch is SecureSignInExpired {
            await failSecureSignIn(SecureSignInRefusal.expired.message, asAlert: true)
        } catch let refusal as SecureSignInRefusal {
            await failSecureSignIn(refusal.message, asAlert: true)
        } catch DSMError.untrustedCertificate(let fingerprint) {
            approvalTask = nil
            state = .editing
            secureSignInRequest = nil
            pendingCertificateFingerprint = fingerprint
            errorMessage = nil
        } catch where DSMError.isCancellation(error) {
            // La demande reste connue de `secureSignInRequest` : elle sera révoquée par
            // l'abandon explicite ou par la tentative suivante, dans une tâche vivante.
            approvalTask = nil
        } catch {
            lastError = error as? DSMError
            await failSecureSignIn(
                (error as? DSMError)?.errorDescription ?? error.localizedDescription,
                asAlert: false
            )
        }
    }

    /// Interroge la décision toutes les cinq secondes, comme le fait DSM lui-même.
    private func awaitApproval(
        client: DSMClient,
        account: String,
        request: SecureSignInRequest
    ) async throws -> String {
        while true {
            let status = try await client.secureSignInStatus(
                account: account,
                requestID: request.requestID
            )
            switch status {
            case .approved(let token):
                return token
            case .waiting(let verifyNumber):
                // Le NAS ne joint pas toujours le chiffre au premier appel : le reprendre
                // ici évite un écran d'attente muet alors que le mobile en affiche un.
                if let verifyNumber, secureSignInRequest?.verifyNumber != verifyNumber {
                    secureSignInRequest = SecureSignInRequest(
                        requestID: request.requestID,
                        verifyNumber: verifyNumber
                    )
                }
            case .denied:
                throw SecureSignInRefusal.denied
            case .expired:
                throw SecureSignInRefusal.expired
            case .revoked:
                throw SecureSignInRefusal.revoked
            }
            try await Task.sleep(for: .seconds(5))
        }
    }

    /// L'issue d'une demande tranchée sur le mobile passe par une alerte : à cet instant
    /// l'écran d'attente est déjà démonté et le formulaire pas encore monté, si bien
    /// qu'aucune vue n'est là pour l'annoncer. L'alerte, elle, prend le focus et est lue
    /// par le système. Un incident technique reste dans le message du formulaire, comme
    /// sur le chemin de connexion classique.
    private func failSecureSignIn(_ message: String, asAlert: Bool) async {
        await revokePendingSecureSignIn()
        approvalTask = nil
        secureSignInRequest = nil
        state = .editing
        if asAlert {
            secureSignInFailure = message
        } else {
            errorMessage = message
        }
    }

    private func revokePendingSecureSignIn() async {
        guard let client, let request = secureSignInRequest else { return }
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        await client.revokeSecureSignIn(account: cleanedAccount, requestID: request.requestID)
    }

    /// Soumission du code de vérification après un 403.
    func submitOTP() async {
        guard let client,
              let endpoint = pendingEndpoint,
              let target = pendingTarget else { return }
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = String(localized: "Saisissez le code de vérification.")
            return
        }

        state = .connecting
        errorMessage = nil

        do {
            let result = try await client.login(
                account: cleanedAccount, password: password,
                otpCode: otpCode.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceID: nil, rememberDevice: rememberDevice
            )
            try await finish(
                with: result,
                account: cleanedAccount,
                target: target,
                endpoint: endpoint
            )
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

    /// Changement du mot de passe imposé par DSM après un 410, puis connexion immédiate
    /// avec le nouveau mot de passe.
    func submitPasswordChange() async {
        guard let client else { return }
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newPassword.isEmpty else {
            errorMessage = String(localized: "Saisissez le nouveau mot de passe.")
            return
        }
        guard newPassword == newPasswordConfirmation else {
            errorMessage = String(localized: "Les deux mots de passe ne correspondent pas.")
            return
        }
        guard newPassword != password else {
            errorMessage = String(localized: "Choisissez un mot de passe différent de l'actuel.")
            return
        }

        state = .connecting
        errorMessage = nil

        do {
            try await client.resetPassword(
                account: cleanedAccount,
                currentPassword: password,
                newPassword: newPassword
            )
        } catch DSMError.untrustedCertificate(let fingerprint) {
            state = .needsPasswordChange
            pendingCertificateFingerprint = fingerprint
            errorMessage = nil
            return
        } catch {
            state = .needsPasswordChange
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return
        }

        VoiceOver.announce(String(localized: "Mot de passe changé."), category: .result)
        // Le mot de passe accepté par DSM devient l'identifiant courant : la connexion
        // reprend le chemin normal, qui sait déjà traiter le code 2FA et le certificat.
        password = newPassword
        newPassword = ""
        newPasswordConfirmation = ""
        await connect(reusingPendingClient: true)
    }

    /// Renonce au changement de mot de passe et revient au formulaire d'identifiants.
    func cancelPasswordChange() {
        state = .editing
        newPassword = ""
        newPasswordConfirmation = ""
        errorMessage = nil
    }

    /// Annule la saisie du code et revient au formulaire d'identifiants.
    func cancelOTP() {
        state = .editing
        otpCode = ""
        errorMessage = nil
    }

    func approvePendingCertificate() async {
        guard let fingerprint = pendingCertificateFingerprint,
              let client else { return }
        let interruptedStep = state
        guard client.approveServerCertificate(fingerprint: fingerprint) else {
            pendingCertificateFingerprint = nil
            errorMessage = String(localized: "Le certificat n'a pas pu être enregistré dans le trousseau.")
            return
        }
        pendingCertificateFingerprint = nil
        switch interruptedStep {
        case .needsOTP:
            await submitOTP()
        case .needsPasswordChange:
            await submitPasswordChange()
        default:
            await connect(reusingPendingClient: true)
        }
    }

    func rejectPendingCertificate() {
        pendingCertificateFingerprint = nil
        client = nil
        pendingEndpoint = nil
        pendingTarget = nil
        state = .editing
    }

    // MARK: - Interne

    /// `storesPassword` est faux quand la session a été ouverte sans mot de passe : il n'y
    /// a rien à mémoriser, et écrire la chaîne vide dans le trousseau condamnerait la
    /// reconnexion automatique du prochain lancement.
    private func finish(
        with result: LoginResult,
        account: String,
        target: NASConnectionTarget,
        endpoint: DSMEndpoint,
        storesPassword: Bool = true
    ) async throws {
        guard let client else { return }
        let capabilities: DSMCapabilities
        do {
            capabilities = try await client.discoverCapabilities()
        } catch {
            try? await client.logout()
            throw error
        }
        if rememberDevice, let did = result.did, !did.isEmpty {
            CredentialStore.remember(deviceID: did, account: account, target: target)
        }
        // Mémoriser (ou oublier) le mot de passe selon le choix « Rester connecté ».
        let remembersPassword: Bool
        if !storesPassword {
            // Une connexion approuvée sur le mobile ne dit rien du mot de passe : celui
            // qui était déjà mémorisé le reste, aucun n'est créé.
            remembersPassword = CredentialStore.password(account: account, target: target) != nil
        } else if rememberPassword {
            remembersPassword = CredentialStore.remember(
                password: password,
                account: account,
                target: target
            )
            rememberPassword = remembersPassword
        } else {
            CredentialStore.forget(account: account, target: target)
            remembersPassword = false
        }
        // « Rester connecté » conserve la session elle-même : c'est ce qui évite, à la
        // prochaine ouverture, un login complet ou une nouvelle approbation sur le mobile.
        if rememberPassword, let stored = StoredDSMSession(result) {
            CredentialStore.rememberSession(stored, account: account, target: target)
        } else {
            CredentialStore.forgetSession(account: account, target: target)
        }
        enterSession(
            account: account,
            target: target,
            endpoint: endpoint,
            capabilities: capabilities,
            remembersPassword: remembersPassword
        )
    }

    /// Dernière étape commune au login et à la reprise d'une session mémorisée.
    private func enterSession(
        account: String,
        target: NASConnectionTarget,
        endpoint: DSMEndpoint,
        capabilities: DSMCapabilities,
        remembersPassword: Bool
    ) {
        guard let client else { return }
        persistPreferences(account: account, target: target)
        session.establish(
            target: target,
            endpoint: endpoint,
            client: client,
            capabilities: capabilities,
            account: account,
            remembersPassword: remembersPassword
        )
        // RootView bascule automatiquement vers l'écran de contenu.
        state = .editing
        errorMessage = nil
        lastError = nil
        password = ""
        otpCode = ""
    }

    private var hasTransientNetworkFailure: Bool {
        if case .network = lastError { return true }
        return false
    }

    private var connectionTarget: NASConnectionTarget? {
        switch connectionMethod {
        case .direct:
            guard let port else { return nil }
            return Self.directTarget(host: host, useHTTPS: useHTTPS, port: port)
        case .quickConnect:
            let id = quickConnectID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard QuickConnectResolver.isValid(id: id) else { return nil }
            return .quickConnect(id: id)
        }
    }

    private var connectionValidationMessage: String {
        switch connectionMethod {
        case .direct where host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            String(localized: "Veuillez renseigner l’adresse du NAS.")
        case .direct:
            String(localized: "Le port doit être un nombre compris entre 1 et 65535.")
        case .quickConnect:
            String(localized: "L’identifiant QuickConnect n’est pas valide.")
        }
    }

    private func resolvedEndpoint(for target: NASConnectionTarget) async throws -> DSMEndpoint {
        switch target {
        case .direct(let endpoint):
            endpoint
        case .quickConnect(let id):
            try await quickConnectResolver.resolve(id: id).endpoint
        }
    }

    private static func directTarget(
        host: String,
        useHTTPS: Bool,
        port: Int
    ) -> NASConnectionTarget? {
        let cleanedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedHost.isEmpty else { return nil }
        return .direct(DSMEndpoint(useHTTPS: useHTTPS, host: cleanedHost, port: port))
    }

    private func persistPreferences(account: String, target: NASConnectionTarget) {
        if let endpoint = target.directEndpoint {
            Preferences.lastHost = endpoint.host
            Preferences.lastPort = endpoint.port
            Preferences.lastUseHTTPS = endpoint.useHTTPS
        } else {
            Preferences.lastHost = ""
            Preferences.lastPort = nil
            Preferences.lastUseHTTPS = true
        }
        Preferences.lastAccount = account
    }
}
