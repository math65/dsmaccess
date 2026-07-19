import Testing
@testable import dsmaccess

@MainActor
struct ConnectionValidationTests {
    @Test func acceptsOnlyValidTCPPorts() {
        let model = ConnectionViewModel(session: SessionStore())
        model.host = "nas.local"
        model.account = "alex"
        model.password = "secret"

        model.portText = "5001"
        #expect(model.port == 5001)
        #expect(model.canSubmit)

        for invalid in ["", "abc", "0", "65536", "-1"] {
            model.portText = invalid
            #expect(model.port == nil)
            #expect(!model.canSubmit)
        }
    }

    @Test func rejectsFieldsContainingOnlyWhitespaceAndNewlines() {
        let model = ConnectionViewModel(session: SessionStore())
        model.host = "\n\t"
        model.account = "alex"
        model.password = "secret"
        model.portText = "5001"
        #expect(!model.canSubmit)

        model.host = "nas.local"
        model.account = " \n"
        #expect(!model.canSubmit)
    }

    @Test func separatesCredentialsBySchemeAndNormalizesHostCase() {
        let https = DSMEndpoint(useHTTPS: true, host: "NAS.Local", port: 5001)
        let http = DSMEndpoint(useHTTPS: false, host: "nas.local", port: 5001)

        #expect(https.credentialStoreKey(account: "alex") == "alex@https://nas.local:5001")
        #expect(http.credentialStoreKey(account: "alex") == "alex@http://nas.local:5001")
        #expect(https.credentialStoreKey(account: "alex") != http.credentialStoreKey(account: "alex"))
    }

    @Test func approvedCertificateIsAvailableToTheActiveSession() {
        let endpoint = DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001)
        let fingerprint = "AA:BB:CC"
        let delegate = ServerTrustDelegate(
            endpoint: endpoint,
            approvedFingerprint: nil,
            persistApprovedFingerprint: { _ in true }
        )

        #expect(delegate.approve(fingerprint: fingerprint))
        #expect(delegate.isApproved(fingerprint: fingerprint))
        #expect(!delegate.isApproved(fingerprint: "DD:EE:FF"))
    }
}
