//
//  DSMResponse.swift
//  dsmaccess
//
//  Enveloppe générique de toutes les réponses de la WebAPI Synology.
//  Une réponse DSM a toujours la forme { "success": Bool, "data": {...}?, "error": { "code": Int }? }.
//

import Foundation

/// Réponse générique de la WebAPI DSM, paramétrée par le type de la charge utile `data`.
struct DSMResponse<T: Decodable & Sendable>: nonisolated Decodable, Sendable {
    let success: Bool
    let data: T?
    let error: DSMErrorBody?
}

/// Corps d'erreur renvoyé par DSM quand `success == false`.
struct DSMErrorBody: nonisolated Decodable, Sendable {
    let code: Int
    let errors: [DSMErrorDetail]?

    init(code: Int, errors: [DSMErrorDetail]? = nil) {
        self.code = code
        self.errors = errors
    }
}

/// Détail optionnel associé à un élément lorsque DSM refuse une opération groupée.
struct DSMErrorDetail: nonisolated Decodable, Equatable, Sendable {
    let code: Int
    let path: String?
    let name: String?
    let id: String?
}

/// Charge utile vide, pour les appels dont on ignore le contenu de `data` (ex. logout).
struct EmptyData: nonisolated Decodable, Sendable {}
