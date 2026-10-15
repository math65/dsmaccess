import Foundation
import Testing
@testable import dsmaccess

struct RedirectPolicyTests {
    private let secure = DSMEndpoint(useHTTPS: true, host: "NAS.example.com", port: 5001)
    private let plain = DSMEndpoint(useHTTPS: false, host: "nas.example.com", port: 5000)

    @Test func followsARedirectWithinTheSameNAS() throws {
        #expect(secure.acceptsRedirect(to: try #require(URL(string: "https://nas.example.com:5001/webapi/entry.cgi"))))
        #expect(secure.acceptsRedirect(to: try #require(URL(string: "https://nas.example.com:443/webapi/entry.cgi"))))
    }

    @Test func followsAnUpgradeToHTTPS() throws {
        #expect(plain.acceptsRedirect(to: try #require(URL(string: "https://nas.example.com:5001/webapi/entry.cgi"))))
    }

    @Test func refusesADowngradeToHTTP() throws {
        #expect(!secure.acceptsRedirect(to: try #require(URL(string: "http://nas.example.com:5000/webapi/entry.cgi"))))
    }

    @Test func refusesAnotherHost() throws {
        #expect(!secure.acceptsRedirect(to: try #require(URL(string: "https://elsewhere.example.net:5001/webapi/entry.cgi"))))
        #expect(!plain.acceptsRedirect(to: try #require(URL(string: "http://nas.example.com.evil.example/webapi"))))
    }

    @Test func refusesAnotherScheme() throws {
        #expect(!secure.acceptsRedirect(to: try #require(URL(string: "ftp://nas.example.com/file"))))
    }

    @Test func theSessionDelegateDropsARefusedRedirect() async throws {
        let delegate = ServerTrustDelegate(
            endpoint: secure,
            approvedFingerprint: nil,
            persistApprovedFingerprint: { _ in true }
        )
        let origin = try #require(URL(string: "https://nas.example.com:5001/"))
        let task = URLSession.shared.dataTask(with: origin)
        let response = try #require(HTTPURLResponse(
            url: origin,
            statusCode: 302,
            httpVersion: nil,
            headerFields: nil
        ))

        let downgrade = try #require(URL(string: "http://nas.example.com:5000/"))
        let sameNAS = try #require(URL(string: "https://nas.example.com:5001/other"))

        let refused = await withCheckedContinuation { continuation in
            delegate.urlSession(
                .shared,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: downgrade),
                completionHandler: { continuation.resume(returning: $0) }
            )
        }
        let followed = await withCheckedContinuation { continuation in
            delegate.urlSession(
                .shared,
                task: task,
                willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: sameNAS),
                completionHandler: { continuation.resume(returning: $0) }
            )
        }

        #expect(refused == nil)
        #expect(followed?.url?.path() == "/other")
    }
}
