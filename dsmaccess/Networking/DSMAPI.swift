//
//  DSMAPI.swift
//  dsmaccess
//
//  Description d'une API DSM et résolution de sa route/version à partir de SYNO.API.Info.
//

import Foundation

nonisolated struct DSMAPI: Hashable, Sendable {
    let name: String
    let preferredVersion: Int?
    let minimumVersion: Int

    init(_ name: String, preferredVersion: Int? = nil, minimumVersion: Int = 1) {
        self.name = name
        self.preferredVersion = preferredVersion
        self.minimumVersion = minimumVersion
    }
}

nonisolated struct ResolvedDSMAPI: Equatable, Sendable {
    let name: String
    let path: String
    let version: Int
    let requestFormat: String?
}

nonisolated struct DSMCapabilities: Equatable, Sendable {
    private(set) var entries: [String: APIInfoEntry] = [:]

    var names: Set<String> { Set(entries.keys) }

    mutating func merge(_ discovered: [String: APIInfoEntry]) {
        entries.merge(discovered) { _, new in new }
    }

    func supports(_ name: String) -> Bool {
        entries[name] != nil
    }

    func supports(_ api: DSMAPI) -> Bool {
        guard let entry = entries[api.name] else { return false }
        let highestAllowed = api.preferredVersion.map { min($0, entry.maxVersion) } ?? entry.maxVersion
        return highestAllowed >= max(api.minimumVersion, entry.minVersion)
    }

    func supports(prefix: String) -> Bool {
        entries.keys.contains { $0.hasPrefix(prefix) }
    }

    func entry(for name: String) -> APIInfoEntry? {
        entries[name]
    }

    func resolve(_ api: DSMAPI) throws -> ResolvedDSMAPI {
        guard let entry = entries[api.name] else {
            throw DSMError.unsupportedAPI(api.name)
        }

        let highestAllowed = api.preferredVersion.map { min($0, entry.maxVersion) } ?? entry.maxVersion
        let lowestAllowed = max(api.minimumVersion, entry.minVersion)
        guard highestAllowed >= lowestAllowed else {
            throw DSMError.unsupportedAPIVersion(api.name)
        }

        return ResolvedDSMAPI(
            name: api.name,
            path: entry.path,
            version: highestAllowed,
            requestFormat: entry.requestFormat
        )
    }
}
