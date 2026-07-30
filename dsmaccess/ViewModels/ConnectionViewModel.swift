//
//  ConnectionViewModel.swift
//  dsmaccess
//
//  Connection state machine: input → attempt → (2FA code if requested) → connected.
//  The code screen appears ONLY if DSM returns "code required" (error 403).
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

    /// How the account proves its identity. The choice drives the form: sign-in approved on
    /// the phone asks for no password at all.
    enum AuthenticationMethod: String, Hashable {
        case password
        case secureSignIn
    }

    enum State: Equatable {
        case editing      // entering credentials
        case resolvingQuickConnect
        case connecting   // attempt in progress
        case needsOTP     // DSM asks for a verification code
        case needsPasswordChange // DSM requires a new password before opening the session
        case awaitingApproval    // passwordless sign-in: decision pending on the phone
    }

    // Form fields (pre-filled from preferences when available).
    var connectionMethod: ConnectionMethod
    /// Remembered from one launch to the next: someone who signs in by approving on their
    /// phone does so every time, and finding "Password" selected at each launch would force
    /// them to flip the picker back before anything else.
    var authenticationMethod: AuthenticationMethod = Preferences.authenticationMethod {
        didSet { Preferences.authenticationMethod = authenticationMethod }
    }
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
    /// "Stay signed in": remember the password for automatic reconnection.
    var rememberPassword: Bool

    private(set) var state: State = .editing
    /// Approval request in progress; carries the number to confirm when the NAS includes one.
    private(set) var secureSignInRequest: SecureSignInRequest?
    /// Outcome of an approval request that did not succeed, presented as an alert.
    var secureSignInFailure: String?
    private var approvalTask: Task<Void, Never>?
    /// Automatic reconnection in progress at launch (hides the form).
    private(set) var isRestoring: Bool
    /// Error message to display and announce (nil if none).
    var errorMessage: String?
    /// Fingerprint of an untrusted certificate, awaiting an explicit decision.
    private(set) var pendingCertificateFingerprint: String?
    /// Last typed error (used to decide whether to forget a stale remembered password).
    private var lastError: DSMError?
    /// Prevents automatic reconnection from running more than once.
    private var hasRunStartup = false
    /// Non-nil when this connection screen follows a session expiry: if automatic
    /// reconnection succeeds, the connected interface must say so.
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
        // Resume is possible at launch: a remembered session first, a password otherwise.
        // The session does not depend on `rememberPassword`, since a passwordless sign-in
        // stores no password at all.
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

    // Unit tests hosted by the app must touch neither the Keychain nor the NAS: reading the
    // Keychain triggers the system prompt and suspends the test runner.
    private static var isRunningHostedTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["DSM_ACCESS_BACKGROUND_TESTS"] == "YES"
            || environment["XCTestConfigurationFilePath"] != nil
    }

    /// Validated port. A non-numeric or out-of-range entry is never silently replaced.
    var port: Int? {
        guard let value = Int(portText), (1...65_535).contains(value) else { return nil }
        return value
    }

    var canSubmit: Bool {
        connectionTarget != nil
            && !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && state == .editing
            // Sign-in approved on the phone only asks for the user name.
            && (authenticationMethod == .secureSignIn || !password.isEmpty)
    }

    /// Routing for the single sign-in button.
    func submit() async {
        switch authenticationMethod {
        case .password: await connect()
        case .secureSignIn: startSecureSignIn()
        }
    }

    var portValidationMessage: String? {
        guard connectionMethod == .direct else { return nil }
        guard port == nil else { return nil }
        return String(localized: "connection.port.error")
    }

    var quickConnectValidationMessage: String? {
        guard connectionMethod == .quickConnect else { return nil }
        let id = quickConnectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !QuickConnectResolver.isValid(id: id) else { return nil }
        return String(localized: "common.error.invalid_quickconnect_id")
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
            String(localized: "connection.status.quickconnect_lookup")
        case .connecting:
            String(localized: "connection.status.connecting")
        case .editing, .needsOTP, .needsPasswordChange, .awaitingApproval:
            nil
        }
    }

    /// Adjusts the default port when toggling HTTP/HTTPS, unless the user entered a custom
    /// port.
    func syncDefaultPortIfNeeded() {
        let httpDefault = String(DSMEndpoint.defaultPort(useHTTPS: false))
        let httpsDefault = String(DSMEndpoint.defaultPort(useHTTPS: true))
        if portText == httpDefault || portText == httpsDefault || portText.isEmpty {
            portText = String(DSMEndpoint.defaultPort(useHTTPS: useHTTPS))
        }
    }

    // MARK: - Actions

    /// First attempt: credentials only (+ remembered device token if present).
    func connect() async {
        await connect(reusingPendingClient: false)
    }

    private func connect(reusingPendingClient: Bool) async {
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAccount.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "connection.credentials.error")
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

    /// Automatic reconnection at launch, if a password is remembered for this NAS.
    /// Reuses `connect()`; if the password is refused (stale), it is forgotten so we do not
    /// retry in a loop at the next launch.
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

    /// Reopens the remembered session without asking the user for anything. True if it is
    /// still valid and the app got in.
    ///
    /// API discovery proves nothing: `SYNO.API.Info` answers without a session. An
    /// authenticated call is required — hence the probe — otherwise a dead session would
    /// pass for good until the first real operation, which would fail without explanation.
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
            // The only case where the session really is at fault: do not retry it at the
            // next launch, and let the usual path take over.
            CredentialStore.forgetSession(account: account, target: target)
            client = nil
            errorMessage = String(
                localized: "connection.saved_session.expired.error"
            )
            return false
        } catch let error as DSMError where error.provesSessionIsAlive {
            // The NAS authenticated us then refused this API: the session is good, it is the
            // account that has no right to access it.
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
            // Network unreachable, certificate refused: the remembered session is not at
            // fault and must survive. The usual path will display the incident.
            client = nil
            return false
        }
    }

    /// Passwordless sign-in: the NAS sends an approval request to the Synology mobile app,
    /// then the app waits for the decision. No password is entered or transmitted, which
    /// often makes this the most practical path with VoiceOver.
    func startSecureSignIn() {
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAccount.isEmpty else {
            errorMessage = String(localized: "connection.username.error")
            return
        }
        guard let target = connectionTarget else {
            errorMessage = connectionValidationMessage
            return
        }
        // A request left pending by a previous attempt must be revoked before opening
        // another one, otherwise it stays approvable on the phone. The revocation is issued
        // from the new task: started from the old one, which we just cancelled, the request
        // would be interrupted before reaching the NAS.
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

    /// User-requested abandon: the request is revoked on the NAS so as not to leave a valid
    /// approval behind.
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
                    localized: "connection.passwordless.unavailable.error"
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
            // The request stays known to `secureSignInRequest`: it will be revoked by the
            // explicit abandon or by the next attempt, from a live task.
            approvalTask = nil
        } catch {
            lastError = error as? DSMError
            await failSecureSignIn(
                (error as? DSMError)?.errorDescription ?? error.localizedDescription,
                asAlert: false
            )
        }
    }

    /// Polls the decision every five seconds, the way DSM itself does.
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
                // The NAS does not always include the number on the first call: picking it
                // up here avoids a silent waiting screen while the phone displays one.
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

    /// The outcome of a request decided on the phone goes through an alert: at that moment
    /// the waiting screen is already torn down and the form not yet mounted, so no view is
    /// there to announce it. The alert, on the other hand, takes focus and is read by the
    /// system. A technical incident stays in the form's message, as on the classic sign-in
    /// path.
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

    /// Submits the verification code after a 403.
    func submitOTP() async {
        guard let client,
              let endpoint = pendingEndpoint,
              let target = pendingTarget else { return }
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = String(localized: "connection.verification_code.error")
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

    /// Password change required by DSM after a 410, then immediate sign-in with the new
    /// password.
    func submitPasswordChange() async {
        guard let client else { return }
        let cleanedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newPassword.isEmpty else {
            errorMessage = String(localized: "connection.new_password.error")
            return
        }
        guard newPassword == newPasswordConfirmation else {
            errorMessage = String(localized: "connection.password_confirmation.error")
            return
        }
        guard newPassword != password else {
            errorMessage = String(localized: "connection.password_change.same_password.error")
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

        VoiceOver.announce(String(localized: "connection.password_change.success"), category: .result)
        // The password accepted by DSM becomes the current credential: sign-in resumes the
        // normal path, which already knows how to handle the 2FA code and the certificate.
        password = newPassword
        newPassword = ""
        newPasswordConfirmation = ""
        await connect(reusingPendingClient: true)
    }

    /// Gives up on the password change and returns to the credentials form.
    func cancelPasswordChange() {
        state = .editing
        newPassword = ""
        newPasswordConfirmation = ""
        errorMessage = nil
    }

    /// Cancels code entry and returns to the credentials form.
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
            errorMessage = String(localized: "connection.certificate.keychain.error")
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

    // MARK: - Internal

    /// `storesPassword` is false when the session was opened without a password: there is
    /// nothing to remember, and writing the empty string into the Keychain would doom the
    /// automatic reconnection at the next launch.
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
        // Remember (or forget) the password according to the "Stay signed in" choice.
        let remembersPassword: Bool
        if !storesPassword {
            // A sign-in approved on the phone says nothing about the password: one that was
            // already remembered stays so, and none is created.
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
        // "Stay signed in" keeps the session itself: that is what avoids, at the next
        // launch, a full login or another approval on the phone.
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

    /// Final step shared by login and by resuming a remembered session.
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
        // RootView automatically switches to the content screen.
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
            String(localized: "connection.address.error")
        case .direct:
            String(localized: "connection.port.error")
        case .quickConnect:
            String(localized: "common.error.invalid_quickconnect_id")
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
