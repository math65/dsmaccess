//
//  ServerTrustDelegate.swift
//  dsmaccess
//
//  Strict TLS validation with explicit, persistent approval of the self-signed
//  certificates used by local NAS units.
//

import CryptoKit
import Foundation
import Security

/// Valid certificates follow the system policy. An invalid certificate is accepted only
/// if its SHA-256 fingerprint matches the one approved earlier.
final class ServerTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let endpoint: DSMEndpoint
    private let persistApprovedFingerprint: @Sendable (String) -> Bool
    private let lock = NSLock()
    private var approvedFingerprint: String?
    private var rejectedFingerprint: String?

    init(endpoint: DSMEndpoint) {
        self.endpoint = endpoint
        self.approvedFingerprint = KeychainStore.load(
            service: KeychainStore.serverTrustService,
            account: endpoint.trustStoreKey
        )
        persistApprovedFingerprint = { fingerprint in
            KeychainStore.save(
                fingerprint,
                service: KeychainStore.serverTrustService,
                account: endpoint.trustStoreKey
            )
        }
    }

    init(
        endpoint: DSMEndpoint,
        approvedFingerprint: String?,
        persistApprovedFingerprint: @escaping @Sendable (String) -> Bool
    ) {
        self.endpoint = endpoint
        self.approvedFingerprint = approvedFingerprint
        self.persistApprovedFingerprint = persistApprovedFingerprint
    }

    /// Forgets the fingerprint approved for this endpoint, so a certificate presented later
    /// must be approved again. Used when its NAS profile is removed: an approval granted by
    /// mistake must not outlive the server it was granted for.
    static func forgetApprovedFingerprint(for endpoint: DSMEndpoint) {
        KeychainStore.delete(
            service: KeychainStore.serverTrustService,
            account: endpoint.trustStoreKey
        )
    }

    func approve(fingerprint: String) -> Bool {
        guard persistApprovedFingerprint(fingerprint) else { return false }
        lock.lock()
        approvedFingerprint = fingerprint
        lock.unlock()
        return true
    }

    func isApproved(fingerprint: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return approvedFingerprint == fingerprint
    }

    func consumeRejectedFingerprint() -> String? {
        lock.lock()
        defer { lock.unlock() }
        defer { rejectedFingerprint = nil }
        return rejectedFingerprint
    }

    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host.caseInsensitiveCompare(endpoint.host) == .orderedSame,
              challenge.protectionSpace.port == endpoint.port,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if SecTrustEvaluateWithError(trust, nil) {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let fingerprint = Self.leafFingerprint(for: trust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if isApproved(fingerprint: fingerprint) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            lock.lock()
            rejectedFingerprint = fingerprint
            lock.unlock()
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private static func leafFingerprint(for trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first else {
            return nil
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
        return digest.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
