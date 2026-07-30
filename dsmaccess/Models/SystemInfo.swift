//
//  SystemInfo.swift
//  dsmaccess
//
//  Payload of SYNO.DSM.Info (method=getinfo): the NAS's basic system information.
//

import Foundation

/// Basic system information about the NAS.
struct SystemInfo: nonisolated Decodable, Sendable {
    let model: String
    let serial: String
    let ram: Int?
    let versionString: String
    let uptime: Int?
    let temperature: Int?
    let temperatureWarn: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case serial
        case ram
        case versionString = "version_string"
        case uptime
        case temperature
        case temperatureWarn = "temperature_warn"
    }
}
