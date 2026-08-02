//
//  SurveillanceCamera.swift
//  dsmaccess
//
//  Surveillance Station cameras and the stream settings useful for the inventory.
//

import Foundation

struct SurveillanceCamera: nonisolated Decodable, Identifiable, Hashable, Sendable {
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

    /// The readable state lives here rather than in the view because the table sorts on it:
    /// sorting the raw code would order the rows by a number the column never shows.
    var statusDescription: String {
        switch status {
        case 1: String(localized: "surveillance.camera.status.normal")
        case 2: String(localized: "surveillance.camera.status.deleted")
        case 3: String(localized: "surveillance.camera.status.disconnected")
        case 4: String(localized: "common.status.unavailable")
        case 5: String(localized: "surveillance.camera.status.ready")
        case 6: String(localized: "common.status.unreachable")
        case 7: String(localized: "common.status.disabled.feminine")
        case 8: String(localized: "surveillance.camera.status.unrecognized")
        case 9: String(localized: "surveillance.camera.configuration")
        case 10: String(localized: "surveillance.camera.status.server_disconnected")
        case 11: String(localized: "surveillance.camera.status.migrating")
        case 13: String(localized: "surveillance.camera.status.storage_removed")
        case 14: String(localized: "common.status.stopping")
        case 15: String(localized: "surveillance.camera.connection_history.unavailable")
        case 16: String(localized: "surveillance.camera.status.unauthorized")
        case 17: String(localized: "surveillance.camera.status.rtsp_error")
        case 18: String(localized: "surveillance.camera.status.no_video")
        default: String(localized: "common.status.unknown")
        }
    }

    /// Codec names are trademarks, not translatable text.
    var codecName: String? {
        switch videoCodec {
        case 1: "MJPEG"
        case 2: "MPEG-4"
        case 3: "H.264"
        case 5: "MXPEG"
        case 6: "H.265"
        case 7: "H.264+"
        default: nil
        }
    }

    /// The address as it is dialled, port included when DSM reports one.
    var addressWithPort: String? {
        guard let address else { return nil }
        guard let port else { return address }
        return "\(address):\(port)"
    }

    /// Non-optional sort keys: a missing value sorts first rather than preventing its column
    /// from being sorted at all.
    var sortableStatus: String { statusDescription }
    var sortableAddress: String { addressWithPort ?? "" }
    var sortableVendor: String { vendor ?? "" }
    var sortableModel: String { model ?? "" }
    var sortableResolution: String { resolution ?? "" }
    var sortableCodec: String { codecName ?? "" }
    /// Sorted as text like `NASConnection.sortableTwoFactor`: `Bool` is not `Comparable`, and
    /// the column must be sortable like the others.
    var sortableEnabled: String { enabled ? "1" : "0" }

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, status, port, vendor, model, resolution
        case address = "ip"
        case host
        case framesPerSecond = "fps"
        case videoCodec
        case stream1
    }

    enum StreamKeys: String, CodingKey { case resolution, fps }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.requiredFlexString(.id)
        name = values.flexString(.name) ?? String(localized: "surveillance.camera.unnamed")
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

struct SurveillanceCameraList: nonisolated Decodable, Sendable {
    let cameras: [SurveillanceCamera]

    enum CodingKeys: String, CodingKey { case cameras, camera }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cameras = try values.decodeArray(SurveillanceCamera.self, forFirstPresent: [.cameras, .camera])
    }
}
