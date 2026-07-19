//
//  PackageUpdate.swift
//  dsmaccess
//
//  Métadonnées nécessaires à la mise à jour d'un paquet officiel.
//

import Foundation

struct PackageUpdate: Equatable, Identifiable, Sendable {
    let packageID: String
    let version: String
    let downloadURL: URL
    let checksum: String
    let fileSize: Int
    let isBeta: Bool
    let packageType: Int

    var id: String {
        [
            packageID.lowercased(),
            version,
            String(isBeta),
            String(packageType),
            downloadURL.absoluteString,
        ].joined(separator: "|")
    }
}
