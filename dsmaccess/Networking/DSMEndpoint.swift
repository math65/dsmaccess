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
}
