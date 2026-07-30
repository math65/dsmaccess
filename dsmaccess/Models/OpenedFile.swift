//
//  OpenedFile.swift
//  dsmaccess
//
//  Fichiers actuellement ouverts sur le NAS (SYNO.Core.FileHandle get), tels que le
//  sous-onglet « Fichier consulté » du moniteur de ressources les présente.
//
//  Trois particularités relevées sur DSM 7.4 le 30/07/2026 :
//  — `path` est relatif au partage, sans barre oblique initiale, et se **termine par le nom
//    du fichier** : afficher `filename` et `path` côte à côte répéterait le nom.
//  — `user` et `host` valent la chaîne « - » pour un service local du NAS, jamais une chaîne
//    vide ni `null` — même piège que `ProcessGroup`.
//  — `pid` arrive en **chaîne** numérique, là où les autres API du module envoient un nombre.
//

import Foundation

struct OpenedFilePage: nonisolated Decodable, Sendable {
    let files: [OpenedFile]
    /// Nombre total de fichiers ouverts sur le NAS, indépendant de la page demandée.
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case files = "OpenedFiles"
        case total
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        files = try c.decodeIfPresent([OpenedFile].self, forKey: .files) ?? []
        total = c.flexInt(.total)
    }
}

struct OpenedFile: nonisolated Decodable, Sendable, Identifiable {
    let name: String?
    /// Chemin relatif au partage, nom du fichier compris.
    let path: String?
    /// Service qui tient le fichier ouvert : « SMB », « Plex Media Server »…
    let service: String?
    /// Compte ayant ouvert le fichier. `nil` pour un service local du NAS.
    let account: String?
    /// Machine à l'origine de l'accès. `nil` pour un service local du NAS.
    let host: String?
    /// Processus qui tient le fichier. Sert d'identité et, pour DSM, de cible de fermeture.
    let processID: String?

    /// Le NAS n'attribue pas d'identifiant : un même processus peut tenir plusieurs fichiers,
    /// et un même chemin être ouvert par plusieurs processus. Les deux ensemble distinguent.
    var id: String { [processID, path].compactMap { $0 }.joined(separator: "|") }

    var displayName: String { name ?? path ?? "" }

    /// Dossier contenant le fichier, sans répéter son nom. `nil` quand le chemin ne comporte
    /// aucun dossier, plutôt qu'une chaîne vide qui se lirait comme une valeur.
    var folder: String? {
        guard let path else { return nil }
        guard let separator = path.lastIndex(of: "/") else { return nil }
        let parent = String(path[path.startIndex..<separator])
        return parent.isEmpty ? nil : parent
    }

    /// Clés de tri non optionnelles : une valeur absente se range en tête plutôt que
    /// d'empêcher le tri de sa colonne.
    var sortableName: String { displayName }
    var sortableFolder: String { folder ?? "" }
    var sortableService: String { service ?? "" }
    var sortableAccount: String { account ?? "" }
    var sortableHost: String { host ?? "" }

    enum CodingKeys: String, CodingKey {
        case filename, path, service, user, host, pid
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.flexString(.filename)
        path = c.flexString(.path)
        service = c.flexString(.service)
        account = Self.meaningful(c.flexString(.user))
        host = Self.meaningful(c.flexString(.host))
        processID = Self.meaningful(c.flexString(.pid))
    }

    /// DSM écrit « - » quand la valeur ne s'applique pas — pour un service local, il n'y a ni
    /// compte ni machine d'origine. Affichée telle quelle, cette chaîne passerait pour une
    /// donnée du NAS.
    private static func meaningful(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "-" ? nil : trimmed
    }
}
