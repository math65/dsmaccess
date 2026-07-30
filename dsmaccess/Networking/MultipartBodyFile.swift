//
//  MultipartBodyFile.swift
//  dsmaccess
//
//  Builds multipart bodies on disk, without loading the uploaded files into memory.
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
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let output: FileHandle
        do {
            output = try FileHandle(forWritingTo: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        do {
            defer { try? output.close() }
            for key in fields.keys.sorted() {
                try Task.checkCancellation()
                guard let value = fields[key] else { continue }
                let safeKey = dispositionValue(key)
                try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
                try output.write(contentsOf: Data(
                    "Content-Disposition: form-data; name=\"\(safeKey)\"\r\n\r\n\(value)\r\n".utf8
                ))
            }

            try output.write(contentsOf: Data("--\(boundary)\r\n".utf8))
            let safeFieldName = dispositionValue(fileFieldName)
            let safeFilename = dispositionValue(fileURL.lastPathComponent)
            try output.write(contentsOf: Data(
                "Content-Disposition: form-data; name=\"\(safeFieldName)\"; filename=\"\(safeFilename)\"\r\n".utf8
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

    @concurrent
    static func fileSize(at url: URL) async throws -> Int64 {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else {
            throw CocoaError(.fileReadUnknown)
        }
        return Int64(fileSize)
    }

    /// Prevents a local file name from closing or injecting a multipart header.
    nonisolated private static func dispositionValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }
}
