//
//  PackageCatalog.swift
//  dsmaccess
//
//  The Package Center catalogue as DSM serves it: the Synology listing, the beta packages
//  it returns in their own array, and the third-party listing that only answers when
//  `blloadothers` is true.
//

import Foundation

/// Where a catalogue entry comes from. DSM reports it in the `source` field: `syno` for its
/// own listing, `others` for everything published through a package source.
enum PackageCatalogOrigin: String, CaseIterable, Sendable {
    case synology = "syno"
    case community = "others"

    var name: String {
        switch self {
        case .synology: String(localized: "packages.origin.synology")
        case .community: String(localized: "packages.origin.community")
        }
    }
}

/// A DSM package category. DSM returns the names already translated, so they are displayed
/// as they arrive rather than mapped onto keys of our own.
struct PackageCategory: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct PackageCatalog: Equatable, Sendable {
    var packages: [PackageUpdate]
    var categories: [PackageCategory]
    /// Why the third-party listing is missing, when the Synology one came through. A source
    /// that cannot be reached must not empty the whole catalogue, but it must be said.
    var communityFailure: String?

    init(
        packages: [PackageUpdate] = [],
        categories: [PackageCategory] = [],
        communityFailure: String? = nil
    ) {
        self.packages = packages
        self.categories = categories
        self.communityFailure = communityFailure
    }
}
