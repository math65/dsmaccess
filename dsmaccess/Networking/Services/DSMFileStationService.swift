//
//  DSMFileStationService.swift
//  dsmaccess
//
//  Navigation et opérations de base sur les fichiers du NAS.
//

import Foundation

@MainActor
final class DSMFileStationService {
    private static let listAPI = DSMAPI("SYNO.FileStation.List", preferredVersion: 2)
    private static let downloadAPI = DSMAPI("SYNO.FileStation.Download", preferredVersion: 2)
    private static let createFolderAPI = DSMAPI("SYNO.FileStation.CreateFolder", preferredVersion: 2)
    private static let renameAPI = DSMAPI("SYNO.FileStation.Rename", preferredVersion: 2)
    private static let deleteAPI = DSMAPI("SYNO.FileStation.Delete", preferredVersion: 2)
    private static let uploadAPI = DSMAPI("SYNO.FileStation.Upload", preferredVersion: 2)
    private static let copyMoveAPI = DSMAPI("SYNO.FileStation.CopyMove", preferredVersion: 3)
    private static let sharingAPI = DSMAPI("SYNO.FileStation.Sharing", preferredVersion: 3)

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    func shares() async throws -> [FileStationItem] {
        let result = try await transport.value(
            api: Self.listAPI,
            method: "list_share",
            as: FileStationShares.self
        )
        return result.shares
    }

    func items(in folderPath: String) async throws -> [FileStationItem] {
        let result = try await transport.value(
            api: Self.listAPI,
            method: "list",
            parameters: [
                "folder_path": folderPath,
                "additional": "[\"size\",\"time\",\"type\"]",
            ],
            as: FileStationFiles.self
        )
        return result.files
    }

    func download(path: String, to destination: URL) async throws {
        let resolved = try await transport.resolvedAPI(Self.downloadAPI)
        var parameters = try transport.authenticatedParameters()
        parameters["api"] = resolved.name
        parameters["version"] = String(resolved.version)
        parameters["method"] = "download"
        parameters["path"] = path
        parameters["mode"] = "download"

        let url = try transport.makeURL(path: resolved.path, parameters: parameters)
        let (temporaryURL, response) = try await transport.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        if let mimeType = response.mimeType, mimeType.contains("json") {
            let data = (try? Data(contentsOf: temporaryURL)) ?? Data()
            if let response = try? JSONDecoder().decode(DSMResponse<EmptyData>.self, from: data),
               !response.success {
                throw DSMError.apiError(code: response.error?.code ?? -1)
            }
            throw DSMError.invalidResponse
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }

    func createFolder(in folderPath: String, name: String) async throws {
        try await transport.perform(
            api: Self.createFolderAPI,
            method: "create",
            parameters: ["folder_path": folderPath, "name": name]
        )
    }

    func rename(path: String, to name: String) async throws {
        try await transport.perform(
            api: Self.renameAPI,
            method: "rename",
            parameters: ["path": path, "name": name]
        )
    }

    func delete(path: String) async throws {
        try await transport.perform(
            api: Self.deleteAPI,
            method: "delete",
            parameters: ["path": path, "recursive": "true"]
        )
    }

    func upload(fileURL: URL, to folderPath: String) async throws {
        let resolved = try await transport.resolvedAPI(Self.uploadAPI)
        var routeParameters = try transport.authenticatedParameters()
        routeParameters["api"] = resolved.name
        routeParameters["version"] = String(resolved.version)
        routeParameters["method"] = "upload"
        let url = try transport.makeURL(path: resolved.path, parameters: routeParameters)

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        var fields = routeParameters
        fields["path"] = folderPath
        fields["create_parents"] = "true"
        fields["overwrite"] = "false"
        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.appendUTF8("Content-Type: application/octet-stream\r\n\r\n")
        body.append(try Data(contentsOf: fileURL, options: .mappedIfSafe))
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await transport.upload(for: request, from: body)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        let result: DSMResponse<EmptyData>
        do {
            result = try JSONDecoder().decode(DSMResponse<EmptyData>.self, from: data)
        } catch {
            throw DSMError.decoding
        }
        guard result.success else {
            throw DSMError.apiError(code: result.error?.code ?? -1)
        }
    }

    func copyMove(path: String, to destinationFolder: String, removeSource: Bool) async throws {
        let task = try await transport.value(
            api: Self.copyMoveAPI,
            method: "start",
            parameters: [
                "path": path,
                "dest_folder_path": destinationFolder,
                "overwrite": "false",
                "remove_src": removeSource ? "true" : "false",
            ],
            as: CopyMoveTask.self
        )

        for _ in 0..<600 {
            try Task.checkCancellation()
            let status = try await transport.value(
                api: Self.copyMoveAPI,
                method: "status",
                parameters: ["taskid": task.taskid],
                as: CopyMoveStatus.self
            )
            if status.finished { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw DSMError.network(String(localized: "Délai dépassé."))
    }

    func createShareLink(path: String, password: String?, expirationDate: String?) async throws -> String {
        var parameters = ["path": "[\"\(path)\"]"]
        if let password, !password.isEmpty { parameters["password"] = password }
        if let expirationDate, !expirationDate.isEmpty { parameters["date_expired"] = expirationDate }
        let result = try await transport.value(
            api: Self.sharingAPI,
            method: "create",
            parameters: parameters,
            as: SharingLinks.self
        )
        guard let url = result.links.first?.url else {
            throw DSMError.invalidResponse
        }
        return url
    }

    func shareLinks() async throws -> [SharingLink] {
        try await transport.value(
            api: Self.sharingAPI,
            method: "list",
            as: SharingLinks.self
        ).links
    }

    func deleteShareLink(id: String) async throws {
        try await transport.perform(
            api: Self.sharingAPI,
            method: "delete",
            parameters: ["id": id]
        )
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}
