//
//  PackageSource.swift
//  dsmaccess
//
//  Third-party package source configured in DSM Package Center.
//

import Foundation

struct PackageSourceList: nonisolated Decodable, Sendable {
    let items: [PackageSource]
}

struct PackageSource: nonisolated Codable, Equatable, Identifiable, Sendable {
    var name: String
    var feed: String

    var id: String { feed }
}
