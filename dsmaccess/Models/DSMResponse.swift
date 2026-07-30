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
}

/// Empty payload, for calls whose `data` content is ignored (e.g. logout).
struct EmptyData: nonisolated Decodable, Sendable {}
