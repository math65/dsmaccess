//
//  StoredDSMSession.swift
//  dsmaccess
//
//  Session DSM conservée entre deux lancements, pour rouvrir l'app sans repasser par
//  l'écran de connexion. Aucune date d'expiration n'y figure : DSM n'en annonce pas, et
//  une date inventée ferait jeter une session encore valide, ou garder une session morte.
//  Seul un essai réel tranche.
//

import Foundation

nonisolated struct StoredDSMSession: Codable, Equatable, Sendable {
    /// Identifiant de session. Secret au porteur : trousseau uniquement, jamais journalisé.
    let sid: String
    /// Jeton anti-CSRF associé. Sans lui, DSM refuse la session reprise en 119.
    let synoToken: String?

    init(sid: String, synoToken: String?) {
        self.sid = sid
        self.synoToken = synoToken
    }

    init?(_ result: LoginResult) {
        guard !result.sid.isEmpty else { return nil }
        self.init(sid: result.sid, synoToken: result.synotoken)
    }
}
