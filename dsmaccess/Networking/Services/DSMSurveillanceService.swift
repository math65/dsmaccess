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
                "offset": "0",
                "limit": "-1",
                "privCamType": "1",
                "basic": "true",
                "streamInfo": "true",
                "blIncludeDeletedCam": "false",
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
            parameters: [key: ids.sorted().joined(separator: ",")]
        )
    }

    func snapshot(cameraID: String) async throws -> Data {
        let resolved = try await transport.resolvedAPI(Self.cameraAPI)
        guard resolved.version >= 9 else {
            throw DSMError.unsupportedAPIVersion(Self.cameraAPI.name)
        }
        var parameters = try transport.authenticatedParameters()
        parameters["api"] = resolved.name
        parameters["version"] = String(resolved.version)
        parameters["method"] = "GetSnapshot"
        parameters["id"] = cameraID
        parameters["profileType"] = "1"

        let url = try transport.makeURL(path: resolved.path, parameters: parameters)
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
