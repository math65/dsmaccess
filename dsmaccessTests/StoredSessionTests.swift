import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct StoredSessionTests {
    /// The rule that decides the fate of a resumed session. Getting it wrong is costly both
    /// ways: throwing away a valid session asks for an approval on the phone at every
    /// launch; keeping a dead session lets the user into an app that will fail on the first
    /// operation, with nothing to explain it.
    @Test func onlyAnAuthenticatedRefusalProvesTheSessionIsAlive() {
        // The NAS identified the session, then refused the API: it is alive.
        #expect(DSMError.permissionDenied.provesSessionIsAlive)
        #expect(DSMError.unsupportedAPI("SYNO.Core.System").provesSessionIsAlive)
        #expect(DSMError.unsupportedAPIVersion("SYNO.Core.System").provesSessionIsAlive)
        #expect(DSMError.apiError(code: 105, message: nil).provesSessionIsAlive)

        // Nothing reached the NAS, or it answered something else: nothing is proven.
        #expect(!DSMError.sessionExpired.provesSessionIsAlive)
        #expect(!DSMError.network("hôte injoignable").provesSessionIsAlive)
        #expect(!DSMError.untrustedCertificate(fingerprint: "ab:cd").provesSessionIsAlive)
        #expect(!DSMError.decoding(detail: nil).provesSessionIsAlive)
        #expect(!DSMError.cancelled.provesSessionIsAlive)
        #expect(!DSMError.invalidCredentials.provesSessionIsAlive)
    }

    /// The CSRF token travels with the SID: resumed without it, the session would be refused
    /// with 119, which wrongly looks like an expired session.
    @Test func keepsTheTokenAlongsideTheSession() throws {
        let stored = StoredDSMSession(sid: "sid-1", synoToken: "token-1")

        let data = try JSONEncoder().encode(stored)
        let restored = try JSONDecoder().decode(StoredDSMSession.self, from: data)

        #expect(restored == stored)
        #expect(restored.synoToken == "token-1")
    }

    @Test func acceptsASessionWithoutACSRFToken() throws {
        let stored = StoredDSMSession(sid: "sid-1", synoToken: nil)
        let data = try JSONEncoder().encode(stored)

        #expect(try JSONDecoder().decode(StoredDSMSession.self, from: data) == stored)
    }

    /// A login that brings back no SID has nothing to store: without this guard, the next
    /// launch would try to resume an empty session and fail for no visible reason.
    @Test func refusesToStoreALoginWithoutASession() {
        #expect(StoredDSMSession(LoginResult(sid: "", did: nil, synotoken: "t")) == nil)
        #expect(StoredDSMSession(LoginResult(sid: "sid-1", did: nil, synotoken: nil)) != nil)
    }
}
