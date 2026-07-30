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
    /// Identifiant du processus qui porte la session. Vaut 1 pour toutes les sessions web :
    /// il n'identifie donc rien à lui seul, mais `kick_connection` l'exige pour les autres
    /// protocoles.
    let processID: Int?
    /// Jeton d'appareil. Renseigné pour les sessions web, vide pour les autres.
    let deviceID: String?

    /// Le NAS n'attribue pas d'identifiant de session. `did` entre dans la clé parce que
    /// plusieurs sessions web du même compte partagent souvent compte, adresse, protocole et
    /// horodatage : sans lui, elles se confondraient et la sélection porterait sur la mauvaise.
    var id: String {
        [account, address, type, rawTime, deviceID].compactMap { $0 }.joined(separator: "|")
    }

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

    /// Ce que `kick_connection` attend pour retrouver la session à couper. DSM ne l'identifie
    /// pas par une clé unique : il la réidentifie par un quadruplet, et ce quadruplet n'est
    /// pas le même selon le protocole. `nil` quand une valeur indispensable manque — mieux
    /// vaut ne pas proposer la coupure que viser une session au hasard.
    enum KickReference: Sendable, Equatable {
        case web(deviceID: String, account: String, resource: String, address: String)
        case service(processID: Int, type: String, account: String, address: String)
    }

    /// Valeur exacte que DSM place dans `type` pour ses sessions web. Relevée sur DSM 7.4 :
    /// c'est une seule chaîne, barre oblique comprise, et non deux protocoles distincts.
    static let webSessionType = "HTTP/HTTPS"

    var isWebSession: Bool { type == Self.webSessionType }

    var kickReference: KickReference? {
        guard canBeKicked, let account, let address else { return nil }
        if isWebSession {
            // `descr` et `did` partent tels quels : DSM compare des valeurs, une absence
            // vaut chaîne vide comme dans son propre client.
            return .web(
                deviceID: deviceID ?? "",
                account: account,
                resource: descriptionText ?? "",
                address: address
            )
        }
        guard let processID, let type else { return nil }
        return .service(processID: processID, type: type, account: account, address: address)
    }

    enum CodingKeys: String, CodingKey {
        case who, from, type, descr, time, pid, did
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
        processID = c.flexInt(.pid)
        deviceID = c.flexString(.did)
    }
}
