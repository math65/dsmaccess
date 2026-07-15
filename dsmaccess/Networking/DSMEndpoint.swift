//
//  DSMEndpoint.swift
//  dsmaccess
//
//  Décrit comment joindre un NAS : schéma (http/https), hôte, port.
//

import Foundation

/// Point d'accès d'un NAS Synology sur le réseau local.
struct DSMEndpoint: Equatable, Sendable {
    var useHTTPS: Bool
    var host: String
    var port: Int

    var scheme: String { useHTTPS ? "https" : "http" }

    var trustStoreKey: String { "\(host.lowercased()):\(port)" }

    /// Port par défaut de DSM selon le schéma (5000 en HTTP, 5001 en HTTPS).
    static func defaultPort(useHTTPS: Bool) -> Int { useHTTPS ? 5001 : 5000 }
}
