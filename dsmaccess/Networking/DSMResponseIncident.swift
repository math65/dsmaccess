//
//  DSMResponseIncident.swift
//  dsmaccess
//
//  Trace d'une réponse DSM que l'app n'a pas su décoder, proposée au signalement.
//  Ne retient que des NOMS de champs : jamais une valeur, donc jamais un nom de
//  fichier, un chemin, un compte ni un identifiant de session.
//

import Foundation

struct DSMResponseIncident: Identifiable, Equatable, Sendable {
    let id = UUID()
    let api: String
    let method: String
    let version: String
    /// Champs reçus, par emplacement (« data », « data.links[] »…). Noms seuls.
    let receivedFields: [String]
    /// Description technique de l'échec, telle que produite par le décodeur.
    let failure: String

    var signature: String { "\(api)/\(method)" }

    /// Reconstruit la forme d'une réponse sans jamais lire une valeur : clés du
    /// niveau racine, clés de `data`, puis clés du premier élément de chaque tableau.
    /// Un tableau vide ou une valeur simple ne produit rien — il n'y a rien à décrire.
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

    /// Décrit l'échec par le champ et le chemin en cause, sans jamais citer de valeur.
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

/// Collecte les réponses illisibles et n'en propose qu'une à la fois. Une opération
/// qui échoue en boucle ne doit pas empiler les alertes, et un incident déjà écarté
/// ne doit plus revenir de la session : au lecteur d'écran, une alerte répétée rend
/// l'app inutilisable.
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

    /// Rend l'incident accepté au formulaire, une seule fois.
    func consumeAccepted() -> DSMResponseIncident? {
        defer { accepted = nil }
        return accepted
    }
}
