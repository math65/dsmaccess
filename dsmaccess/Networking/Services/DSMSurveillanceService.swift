//
//  DSMSurveillanceService.swift
//  dsmaccess
//
//  Inventaire, activation et instantanés des caméras Surveillance Station.
//

import Foundation

@MainActor
final class DSMSurveillanceService {
    private static let cameraAPI = DSMAPI("SYNO.SurveillanceStation.Camera")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func cameras() async throws -> [SurveillanceCamera] {
        let result = try await transport.value(
            api: Self.cameraAPI,
            method: "List",
            parameters: [
                "offset": .integer(0),
                "limit": .integer(-1),
                "privCamType": .integer(1),
                "basic": .boolean(true),
                "streamInfo": .boolean(true),
                "blIncludeDeletedCam": .boolean(false),
            ],
            as: SurveillanceCameraList.self
        )
        return result.cameras
    }

    func setEnabled(_ enabled: Bool, ids: Set<String>) async throws {
        guard !ids.isEmpty else { return }
        let resolved = try await transport.resolvedAPI(Self.cameraAPI)
        let key = resolved.version >= 9 ? "idList" : "cameraIds"
        try await transport.perform(
            api: Self.cameraAPI,
            method: enabled ? "Enable" : "Disable",
            parameters: [key: .string(ids.sorted().joined(separator: ","))]
        )
    }

    func snapshot(cameraID: String) async throws -> Data {
        let resolved = try await transport.resolvedAPI(Self.cameraAPI)
        guard resolved.version >= 9 else {
            throw DSMError.unsupportedAPIVersion(Self.cameraAPI.name)
        }
        let url = try await transport.makeURL(
            api: Self.cameraAPI,
            method: "GetSnapshot",
            parameters: ["id": .string(cameraID), "profileType": .integer(1)]
        )
        let (data, response) = try await transport.data(for: URLRequest(url: url))
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              data.count > 2,
              data[data.startIndex] == 0xFF,
              data[data.index(after: data.startIndex)] == 0xD8 else {
            throw DSMError.invalidResponse
        }
        return data
    }
}
