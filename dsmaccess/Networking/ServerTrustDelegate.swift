//
//  ServerTrustDelegate.swift
//  dsmaccess
//
//  Validation TLS stricte avec approbation explicite et persistante des certificats
//  auto-signés utilisés par les NAS locaux.
//

import CryptoKit
import Foundation
import Security

/// Les certificats valides suivent la politique système. Un certificat non valide
/// n'est accepté que si son empreinte SHA-256 correspond à celle approuvée auparavant.
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
