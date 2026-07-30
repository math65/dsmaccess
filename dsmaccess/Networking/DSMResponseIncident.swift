//
//  DSMResponseIncident.swift
//  dsmaccess
//
//  Trace of a DSM response the app failed to decode, offered up for reporting.
//  Keeps field NAMES only: never a value, hence never a file name, a path, an
//  account or a session identifier.
//

import Foundation

struct DSMResponseIncident: Identifiable, Equatable, Sendable {
    let id = UUID()
    let api: String
    let method: String
    let version: String
    /// Fields received, by location ("data", "data.links[]"…). Names only.
    let receivedFields: [String]
    /// Technical description of the failure, as produced by the decoder.
    let failure: String

    var signature: String { "\(api)/\(method)" }

    /// Rebuilds the shape of a response without ever reading a value: root-level keys,
    /// keys of `data`, then keys of the first element of each array. An empty array or a
    /// plain value produces nothing — there is nothing to describe.
    static func fields(in data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        var described = ["racine : " + names(of: root)]
        if let payload = root["data"] as? [String: Any] {
            described.append("data : " + names(of: payload))
            for key in payload.keys.sorted() {
                guard let array = payload[key] as? [Any],
                      let first = array.first as? [String: Any] else { continue }
                described.append("data.\(key)[] : " + names(of: first))
            }
        }
        return described
    }

    /// Describes the failure by the field and path involved, without ever quoting a value.
    nonisolated static func summary(of error: Error) -> String {
        guard let decoding = error as? DecodingError else { return "réponse illisible" }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "champ manquant : \(key.stringValue)\(location(context))"
        case .typeMismatch(let type, let context):
            return "type inattendu, \(type) attendu\(location(context))"
        case .valueNotFound(let type, let context):
            return "valeur absente, \(type) attendu\(location(context))"
        case .dataCorrupted(let context):
            return "donnée invalide\(location(context))"
        @unknown default:
            return "réponse illisible"
        }
    }

    private static func location(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "" : " (chemin \(path))"
    }

    private static func names(of object: [String: Any]) -> String {
        let keys = object.keys.sorted()
        return keys.isEmpty ? "aucun champ" : keys.joined(separator: ", ")
    }
}

/// Collects unreadable responses and offers only one at a time. An operation failing in a
/// loop must not pile up alerts, and an incident already dismissed must not come back for
/// the rest of the session: with a screen reader, a repeated alert makes the app unusable.
@MainActor
@Observable
final class DSMResponseIncidents {
    static let shared = DSMResponseIncidents()

    private(set) var pending: DSMResponseIncident?
    private(set) var accepted: DSMResponseIncident?
    private var settled = Set<String>()

    func record(_ incident: DSMResponseIncident) {
        guard pending == nil, !settled.contains(incident.signature) else { return }
        pending = incident
    }

    func acceptPending() {
        guard let pending else { return }
        settled.insert(pending.signature)
        accepted = pending
        self.pending = nil
    }

    func ignorePending() {
        guard let pending else { return }
        settled.insert(pending.signature)
        self.pending = nil
    }

    /// Hands the accepted incident to the form, once only.
    func consumeAccepted() -> DSMResponseIncident? {
        defer { accepted = nil }
        return accepted
    }
}
