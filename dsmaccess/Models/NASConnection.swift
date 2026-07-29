//
//  NASConnection.swift
//  dsmaccess
//
//  Sessions ouvertes sur le NAS (SYNO.Core.CurrentConnection get), telles que l'onglet
//  Connexions du moniteur de ressources les présente.
//
//  Deux mises en garde relevées sur DSM 7.4 le 29/07/2026 :
//  — `descr` vaut « DiskStation Manager » aussi bien pour l'app que pour le client web ;
//    seule l'adresse source distingue les deux.
//  — `time` et `first_login_time` se contredisent d'une entrée à l'autre. DSM affiche
//    `time` dans sa colonne « Heure » : c'est celui-là qui fait foi ici.
//

import Foundation

struct NASConnectionPage: nonisolated Decodable, Sendable {
    let items: [NASConnection]
}

struct NASConnection: nonisolated Decodable, Sendable, Identifiable {
    let account: String?
    let address: String?
    /// Protocole affiché par DSM : « HTTP/HTTPS », « SMB3 »…
    let type: String?
    /// Ressource ou application concernée, selon le protocole.
    let descriptionText: String?
    /// Horodatage brut du NAS, au format « aaaa/MM/jj HH:mm:ss ».
    let rawTime: String?
    let isCurrent: Bool
    let canBeKicked: Bool

    var id: String { [account, address, type, rawTime].compactMap { $0 }.joined(separator: "|") }

    /// Clés de tri non optionnelles : une valeur absente se range en tête plutôt que
    /// d'empêcher le tri de sa colonne.
    var sortableAccount: String { account ?? "" }
    var sortableAddress: String { address ?? "" }
    var sortableType: String { type ?? "" }
    var sortableDescription: String { descriptionText ?? "" }
    var sortableDate: Date { openedAt ?? .distantPast }

    /// Horodatage rendu dans la langue et le fuseau du Mac. DSM n'indiquant pas le fuseau
    /// de sa valeur, elle est lue comme locale — juste tant que le NAS et le Mac partagent
    /// le même, ce qui est le cas courant. La chaîne brute est conservée en repli plutôt
    /// que de n'afficher rien.
    var openedAt: Date? {
        guard let rawTime else { return nil }
        return Self.nasFormatter.date(from: rawTime)
    }

    private static let nasFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case who, from, type, descr, time
        case isCurrent = "is_current_connected"
        case canBeKicked = "can_be_kicked"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = c.flexString(.who)
        address = c.flexString(.from)
        type = c.flexString(.type)
        descriptionText = c.flexString(.descr)
        rawTime = c.flexString(.time)
        isCurrent = c.flexBool(.isCurrent) ?? false
        canBeKicked = c.flexBool(.canBeKicked) ?? false
    }
}
