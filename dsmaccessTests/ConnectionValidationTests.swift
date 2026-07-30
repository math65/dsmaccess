import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct ConnectionValidationTests {
    @Test func acceptsOnlyValidTCPPorts() {
        let model = ConnectionViewModel(session: SessionStore())
        // The mode is set explicitly: init picks up the one from the profile persisted
        // on the machine, and this test validates the direct connection fields.
        model.connectionMethod = .direct
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
        model.connectionMethod = .direct
        model.host = "\n\t"
        model.account = "alex"
        model.password = "secret"
        model.portText = "5001"
        #expect(!model.canSubmit)

        model.host = "nas.local"
        model.account = " \n"
        #expect(!model.canSubmit)
    }

    @Test func validatesAQuickConnectIdentifierInsteadOfDirectAddressFields() {
        let model = ConnectionViewModel(session: SessionStore())
        model.connectionMethod = .quickConnect
        model.quickConnectID = "My-NAS-42"
        model.host = ""
        model.portText = "invalid"
        model.account = "alex"
        model.password = "secret"

        #expect(model.canSubmit)
        #expect(model.portValidationMessage == nil)
        #expect(model.quickConnectValidationMessage == nil)

        model.quickConnectID = "my.nas"
        #expect(!model.canSubmit)
        #expect(model.quickConnectValidationMessage != nil)
    }

    @Test func separatesCredentialsBySchemeAndNormalizesHostCase() {
        let https = DSMEndpoint(useHTTPS: true, host: "NAS.Local", port: 5001)
        let http = DSMEndpoint(useHTTPS: false, host: "nas.local", port: 5001)

        #expect(https.credentialStoreKey(account: "alex") == "alex@https://nas.local:5001")
        #expect(http.credentialStoreKey(account: "alex") == "alex@http://nas.local:5001")
        #expect(https.credentialStoreKey(account: "alex") != http.credentialStoreKey(account: "alex"))
    }

    @Test func quickConnectCredentialsUseTheStableIdentifier() {
        let target = NASConnectionTarget.quickConnect(id: "My-NAS")

        #expect(target.credentialStoreKey(account: "alex") == "alex@quickconnect://my-nas")
        #expect(target == .quickConnect(id: "my-nas"))
    }

    @Test func presentsAQuickConnectResolutionFailure() async {
        let stub = DSMRequestStub(results: [
            .response(Data(#"[{"errno":4,"suberrno":1}]"#.utf8)),
        ])
        let resolver = QuickConnectResolver(requestData: { try await stub.data(for: $0) })
        let model = ConnectionViewModel(
            session: SessionStore(),
            quickConnectResolver: resolver
        )
        model.connectionMethod = .quickConnect
        model.quickConnectID = "missing-nas"
        model.account = "alex"
        model.password = "secret"

        await model.connect()

        #expect(model.state == .editing)
        #expect(model.errorMessage == QuickConnectError.unknownID.errorDescription)
        #expect(await stub.requestCount == 1)
    }

    @Test func cancelledQuickConnectResolutionDoesNotPresentAnError() async {
        let resolver = QuickConnectResolver(requestData: { _ in
            throw CancellationError()
        })
        let model = ConnectionViewModel(
            session: SessionStore(),
            quickConnectResolver: resolver
        )
        model.connectionMethod = .quickConnect
        model.quickConnectID = "my-nas"
        model.account = "alex"
        model.password = "secret"

        await model.connect()

        #expect(model.state == .editing)
        #expect(model.errorMessage == nil)
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
