//
//  APIInfo.swift
//  dsmaccess
//
//  Response of SYNO.API.Info: for each requested API, the real CGI path and the range of
//  supported versions. The paths are NEVER hard-coded, because they vary with the DSM
//  version.
//

import Foundation

/// Details of an API returned by SYNO.API.Info (CGI path relative to /webapi/).
struct APIInfoEntry: nonisolated Decodable, Equatable, Sendable {
    let path: String
    let minVersion: Int
    let maxVersion: Int
    let requestFormat: String?

    init(path: String, minVersion: Int, maxVersion: Int, requestFormat: String? = nil) {
        self.path = path
        self.minVersion = minVersion
        self.maxVersion = maxVersion
        self.requestFormat = requestFormat
    }
}
