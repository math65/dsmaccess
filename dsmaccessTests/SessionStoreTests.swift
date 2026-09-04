import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct SessionStoreTests {
    @Test func reconnectionNoticeLivesUntilDismissedOrSessionCleared() {
        let session = SessionStore()
        #expect(session.reconnectionNotice == nil)

        session.publishAutomaticReconnectionNotice()
        let notice = session.reconnectionNotice
        #expect(notice?.isEmpty == false)

        session.dismissReconnectionNotice()
        #expect(session.reconnectionNotice == nil)

        // A notice still on screen must not survive a sign-out: it would be shown out of
        // context in the next session.
        session.publishAutomaticReconnectionNotice()
        session.clear()
        #expect(session.reconnectionNotice == nil)
    }

    /// The report needs the model and the DSM version. The same payload carries the serial
    /// number, which must never leave the machine.
    @Test func keepsWhatTheNASSaysAboutItselfExceptItsSerialNumber() {
        let session = SessionStore()
        #expect(session.nasModel == nil)
        #expect(session.dsmVersion == nil)

        session.noteSystemInfo(
            SystemInfo(
                model: "DS920+",
                serial: "serie-sentinelle",
                ram: 4096,
                versionString: "DSM 7.4-12345",
                uptime: 1000,
                temperature: 40,
                temperatureWarn: false
            )
        )
        #expect(session.nasModel == "DS920+")
        #expect(session.dsmVersion == "DSM 7.4-12345")

        session.clear()
        #expect(session.nasModel == nil)
        #expect(session.dsmVersion == nil)
    }

    @Test func withClientRejectsWorkAfterLogoutWithoutFakingAnExpiry() async {
        let session = SessionStore()
        do {
            _ = try await session.withClient { _ in }
            Issue.record("Sans session, withClient aurait dû échouer.")
        } catch {
            #expect(DSMError.isCancellation(error))
            #expect(session.disconnectionMessage == nil)
        }
    }
}

/// Removing a profile must purge every secret tied to it. These drive the real `SessionStore`
/// through injected purge hooks, so nothing touches the Keychain; they seed and restore the
/// shared `Preferences`, hence run serialized.
@MainActor
@Suite(.serialized)
struct ProfileSecretPurgeTests {
    /// Runs the body with a single seeded profile and no active selection, restoring the
    /// preferences it touches afterwards.
    private func withSeededProfile(
        _ profile: NASProfile,
        _ body: (SessionStore, _ purgedSecrets: () -> [(account: String, target: NASConnectionTarget)],
                 _ purgedCertificates: () -> [DSMEndpoint]) -> Void
    ) {
        let savedProfiles = Preferences.nasProfiles
        let savedSelected = Preferences.selectedNASProfileID
        let savedRemember = Preferences.rememberPassword
        defer {
            Preferences.nasProfiles = savedProfiles
            Preferences.selectedNASProfileID = savedSelected
            Preferences.rememberPassword = savedRemember
        }
        Preferences.nasProfiles = [profile]
        Preferences.selectedNASProfileID = nil

        var secrets: [(account: String, target: NASConnectionTarget)] = []
        var certificates: [DSMEndpoint] = []
        let session = SessionStore(
            forgetSecrets: { secrets.append(($0, $1)) },
            forgetCertificate: { certificates.append($0) }
        )
        body(session, { secrets }, { certificates })
    }

    @Test func removingADirectProfilePurgesSecretsAndApprovedCertificate() {
        let endpoint = DSMEndpoint(useHTTPS: true, host: "192.0.2.10", port: 5001)
        let profile = NASProfile(
            name: "Test",
            connection: .direct(endpoint),
            account: "nasuser",
            remembersPassword: true
        )
        withSeededProfile(profile) { session, purgedSecrets, purgedCertificates in
            session.removeProfile(profile.id)

            #expect(purgedSecrets().count == 1)
            #expect(purgedSecrets().first?.account == "nasuser")
            #expect(purgedSecrets().first?.target == .direct(endpoint))
            // The approved fingerprint of a direct endpoint must go with the profile.
            #expect(purgedCertificates() == [endpoint])
        }
    }

    @Test func removingAQuickConnectProfilePurgesSecretsWithoutACertificate() {
        let profile = NASProfile(
            name: "QC",
            connection: .quickConnect(id: "MY-NAS"),
            account: "nasuser",
            remembersPassword: false
        )
        withSeededProfile(profile) { session, purgedSecrets, purgedCertificates in
            session.removeProfile(profile.id)

            #expect(purgedSecrets().count == 1)
            #expect(purgedSecrets().first?.target == .quickConnect(id: "MY-NAS"))
            // QuickConnect uses a system-valid certificate: there is no approval to forget.
            #expect(purgedCertificates().isEmpty)
        }
    }
}
