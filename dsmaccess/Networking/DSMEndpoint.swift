//
//  DSMEndpoint.swift
//  dsmaccess
//
//  Describes how to reach a NAS: scheme (http/https), host, port.
//

import Foundation

/// Network endpoint used to reach a Synology NAS.
nonisolated struct DSMEndpoint: Equatable, Sendable {
    var useHTTPS: Bool
    var host: String
    var port: Int

    var scheme: String { useHTTPS ? "https" : "http" }

    var trustStoreKey: String { "\(host.lowercased()):\(port)" }

    func credentialStoreKey(account: String) -> String {
        "\(account)@\(scheme)://\(host.lowercased()):\(port)"
    }

    /// Default DSM port for the scheme (5000 over HTTP, 5001 over HTTPS).
    static func defaultPort(useHTTPS: Bool) -> Int { useHTTPS ? 5001 : 5000 }

    /// The same NAS without the address part QuickConnect adds for a local route.
    ///
    /// QuickConnect names its LAN route by encoding the address into the host —
    /// `192-168-1-15.math65.direct.quickconnect.to` — and DSM does not recognise that form as
    /// one of its own addresses: measured on DSM 7.4, it refuses the terminal's handshake
    /// there and accepts it on `math65.direct.quickconnect.to`, same session and same request.
    /// Reaching the NAS this way leaves the local network, so it is only worth trying once the
    /// address of the connection has been refused.
    var quickConnectHostWithoutLocalPrefix: String? {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 5,
              components.dropFirst().joined(separator: ".").lowercased()
                  .hasSuffix(".direct.quickconnect.to")
                  || components.dropFirst().joined(separator: ".").lowercased()
                      .hasSuffix(".direct.quickconnect.cn") else { return nil }
        // The prefix QuickConnect builds is the address with its separators replaced.
        let prefix = components[0]
        guard !prefix.isEmpty,
              prefix.allSatisfy({ $0.isNumber || $0 == "-" }),
              prefix.contains("-") else { return nil }
        return components.dropFirst().joined(separator: ".")
    }
}
