//
//  DSMResponse.swift
//  dsmaccess
//
//  Generic envelope for every Synology WebAPI response.
//  A DSM response always has the form
//  { "success": Bool, "data": {...}?, "error": { "code": Int }? }.
//

import Foundation

/// Generic DSM WebAPI response, parameterised by the type of the `data` payload.
struct DSMResponse<T: Decodable & Sendable>: nonisolated Decodable, Sendable {
    let success: Bool
    let data: T?
    let error: DSMErrorBody?
}

/// Error body returned by DSM when `success == false`.
struct DSMErrorBody: nonisolated Decodable, Sendable {
    let code: Int
    let errors: [DSMErrorDetail]?

    private enum CodingKeys: String, CodingKey {
        case code
        case errors
    }

    init(code: Int, errors: [DSMErrorDetail]? = nil) {
        self.code = code
        self.errors = errors
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(Int.self, forKey: .code)
        guard container.contains(.errors), try !container.decodeNil(forKey: .errors) else {
            errors = nil
            return
        }
        if let details = try? container.decode([DSMErrorDetail].self, forKey: .errors) {
            errors = details
        } else {
            errors = [try container.decode(DSMErrorDetail.self, forKey: .errors)]
        }
    }
}

/// Optional detail attached to a parameter or an item refused by DSM.
struct DSMErrorDetail: nonisolated Decodable, Equatable, Sendable {
    let code: Int?
    let path: String?
    let name: String?
    let id: String?
    let reason: String?
    /// The explanation DSM attaches to a refusal. Measured on Package Center: the field is
    /// there on a real failure, and empty far more often than not.
    let message: String?

    /// The explanation, or nil when DSM sent the field without filling it. Line breaks are
    /// folded the way the web client folds them before displaying the text.
    nonisolated var explanation: String? {
        guard let message else { return nil }
        let text = message
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Empty payload, for calls whose `data` content is ignored (e.g. logout).
struct EmptyData: nonisolated Decodable, Sendable {}
