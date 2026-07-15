//
//  MultipartBodyFile.swift
//  dsmaccess
//
//  Construction de corps multipart sur disque, sans charger les fichiers envoyés en mémoire.
//

import Foundation

enum MultipartBodyFile {
    @concurrent
    static func create(
        fields: [String: String],
        fileURL: URL,
        fileFieldName: String,
        boundary: String
    ) async throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsmaccess-upload-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else {
            throw DSMError.invalidResponse
        }

        do {
            defer { try? output.close() }
            for key in fields.keys.sorted() {
                try Task.checkCancellation()
                guard let value = fields[key] else { continue }
                try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
                try output.write(contentsOf: Data(
                    "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8
                ))
            }

            try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            try output.write(contentsOf: Data(
                "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".utf8
            ))
            try output.write(contentsOf: Data("Content-Type: application/octet-stream\r\n\r\n".utf8))

            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    @concurrent
    static func readData(at url: URL) async throws -> Data {
        try Task.checkCancellation()
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}
