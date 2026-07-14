//
//  SurveillanceCamera.swift
//  dsmaccess
//
//  Caméras Surveillance Station et réglages de flux utiles à l’inventaire.
//

import Foundation

struct SurveillanceCamera: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let enabled: Bool
    let status: Int
    let address: String?
    let port: Int?
    let vendor: String?
    let model: String?
    let resolution: String?
    let framesPerSecond: Int?
    let videoCodec: Int?

    var isAvailable: Bool { enabled && [1, 5].contains(status) }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, status, port, vendor, model, resolution
        case address = "ip"
        case host
        case framesPerSecond = "fps"
        case videoCodec
        case stream1
    }

    enum StreamKeys: String, CodingKey { case resolution, fps }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = values.flexString(.id) ?? UUID().uuidString
        name = values.flexString(.name) ?? String(localized: "Caméra sans nom")
        status = values.flexInt(.status) ?? 0
        enabled = values.flexBool(.enabled) ?? (status != 7)
        address = values.flexString(.address) ?? values.flexString(.host)
        port = values.flexInt(.port)
        vendor = values.flexString(.vendor)
        model = values.flexString(.model)
        videoCodec = values.flexInt(.videoCodec)

        if let stream = try? values.nestedContainer(keyedBy: StreamKeys.self, forKey: .stream1) {
            resolution = values.flexString(.resolution) ?? stream.flexString(.resolution)
            framesPerSecond = values.flexInt(.framesPerSecond) ?? stream.flexInt(.fps)
        } else {
            resolution = values.flexString(.resolution)
            framesPerSecond = values.flexInt(.framesPerSecond)
        }
    }
}

struct SurveillanceCameraList: Decodable, Sendable {
    let cameras: [SurveillanceCamera]

    enum CodingKeys: String, CodingKey { case cameras, camera }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cameras = (try? values.decode([SurveillanceCamera].self, forKey: .cameras))
            ?? (try? values.decode([SurveillanceCamera].self, forKey: .camera))
            ?? []
    }
}
