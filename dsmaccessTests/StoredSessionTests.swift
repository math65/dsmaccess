import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct StoredSessionTests {
    /// La règle qui décide du sort d'une session reprise. Se tromper ici coûte cher dans
    /// les deux sens : jeter une session valide redemande une approbation sur le mobile à
    /// chaque lancement ; garder une session morte fait entrer dans une app qui échouera
    /// à la première opération, sans que rien l'explique.
    @Test func onlyAnAuthenticatedRefusalProvesTheSessionIsAlive() {
        // Le NAS a identifié la session, puis refusé l'API : elle vit.
        #expect(DSMError.permissionDenied.provesSessionIsAlive)
        #expect(DSMError.unsupportedAPI("SYNO.Core.System").provesSessionIsAlive)
        #expect(DSMError.unsupportedAPIVersion("SYNO.Core.System").provesSessionIsAlive)
        #expect(DSMError.apiError(code: 105).provesSessionIsAlive)

        // Rien n'a atteint le NAS, ou il a répondu autre chose : rien n'est prouvé.
        #expect(!DSMError.sessionExpired.provesSessionIsAlive)
        #expect(!DSMError.network("hôte injoignable").provesSessionIsAlive)
        #expect(!DSMError.untrustedCertificate(fingerprint: "ab:cd").provesSessionIsAlive)
        #expect(!DSMError.decoding(detail: nil).provesSessionIsAlive)
        #expect(!DSMError.cancelled.provesSessionIsAlive)
        #expect(!DSMError.invalidCredentials.provesSessionIsAlive)
    }

    /// Le jeton CSRF voyage avec le SID : repris sans lui, la session se ferait refuser
    /// en 119, ce qui ressemble à tort à une session expirée.
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

    /// Un login qui ne rapporte pas de SID n'a rien à mémoriser : sans cette garde, le
    /// lancement suivant tenterait de reprendre une session vide et échouerait sans raison
    /// visible.
    @Test func refusesToStoreALoginWithoutASession() {
        #expect(StoredDSMSession(LoginResult(sid: "", did: nil, synotoken: "t")) == nil)
        #expect(StoredDSMSession(LoginResult(sid: "sid-1", did: nil, synotoken: nil)) != nil)
    }
}
