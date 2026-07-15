//
//  SystemInfo.swift
//  dsmaccess
//
//  Charge utile de SYNO.DSM.Info (method=getinfo) : infos système de base du NAS.
//

import Foundation

/// Informations système de base du NAS.
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
