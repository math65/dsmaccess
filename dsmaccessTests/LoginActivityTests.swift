import Foundation
import Testing
@testable import dsmaccess

/// Formes relevées sur DSM 7.4 le 30/07/2026. Les valeurs sont inventées : les adresses,
/// villes et coordonnées que le NAS renvoie réellement désignent des personnes.
@MainActor
struct LoginActivityTests {
    /// Une connexion jugée inhabituelle. Le NAS ne fournit pas de phrase mais une clé de son
    /// catalogue et un sac d'arguments : la phrase est rédigée par l'app.
    @Test func readsAnAbnormalLoginAsTheNASSendsIt() throws {
        let payload = Data(#"""
        {"total":1,"items":[
          {"create_time":"2026/07/27 18:41:49","severity":"high","user":"testeur",
           "str_id":"abnormal_login","str_section":"loganalyzer",
           "str_args":{"city":"Villeneuve","country_code":"FR","ip":"192.0.2.10",
             "latitude":0,"longitude":0,"protocol":"DSM","subdivision":"Region",
             "timestamp":"2026/07/27 18:41:49","uid":"1026","user":"testeur",
             "user_agent":"Mozilla/5.0"}}]}
        """#.utf8)

        let page = try JSONDecoder().decode(LoginActivityPage.self, from: payload)
        let event = try #require(page.events.first)

        #expect(page.total == 1)
        #expect(event.kind == .abnormalLogin)
        #expect(event.severity == .high)
        #expect(event.account == "testeur")
        #expect(event.details.address == "192.0.2.10")
        #expect(event.details.city == "Villeneuve")
        #expect(event.details.countryCode == "FR")
        #expect(event.details.protocolName == "DSM")
        #expect(event.recordedAt != nil)
        // Une connexion inhabituelle porte une seule adresse, dans `ip`.
        #expect(event.details.allAddresses == ["192.0.2.10"])
    }

    /// Une attaque par force brute. Ses arguments ne sont pas ceux d'une connexion
    /// inhabituelle : les adresses arrivent en liste, avec un décompte et une fenêtre.
    @Test func readsABruteForceAttackWithItsOwnArguments() throws {
        let payload = Data(#"""
        {"total":1,"items":[
          {"create_time":"2026/07/27 18:41:49","severity":"medium","user":"testeur",
           "str_id":"brute_force_attack","str_section":"loganalyzer",
           "str_args":{"attempt_count":10,"country_code_list":[],
             "has_any_public_src_ip":false,"protocol_list":["DSM"],
             "src_ip_list":["192.0.2.20"],"thresh_minutes":5,"user":"testeur"}}]}
        """#.utf8)

        let event = try #require(
            try JSONDecoder().decode(LoginActivityPage.self, from: payload).events.first
        )

        #expect(event.kind == .bruteForceAttack)
        #expect(event.severity == .medium)
        #expect(event.details.attemptCount == 10)
        #expect(event.details.thresholdMinutes == 5)
        #expect(event.details.addresses == ["192.0.2.20"])
        #expect(event.details.protocolNames == ["DSM"])
        // Pas de ville ni d'adresse unique ici : ces arguments n'existent pas pour cette clé.
        #expect(event.details.city == nil)
        #expect(event.details.address == nil)
    }

    /// Une clé que l'app ne sait pas rédiger doit rester lisible et repérable, pour que
    /// l'écran puisse le dire au lieu d'inventer une phrase.
    @Test func keepsACatalogKeyItCannotPhrase() throws {
        let payload = Data(#"""
        {"total":1,"items":[
          {"create_time":"2026/07/27 18:41:49","severity":"low","user":"testeur",
           "str_id":"some_future_alert","str_section":"loganalyzer","str_args":{}}]}
        """#.utf8)

        let event = try #require(
            try JSONDecoder().decode(LoginActivityPage.self, from: payload).events.first
        )

        #expect(event.kind == .unknown(section: "loganalyzer", identifier: "some_future_alert"))
        #expect(event.severity == .low)
        #expect(event.details.allAddresses.isEmpty)
    }

    /// Les gravités se trient par sévérité, et non par ordre alphabétique.
    @Test func sortsSeveritiesBySeverity() {
        let severities: [LoginActivityEvent.Severity] = [.high, .low, .medium]

        #expect(severities.sorted { $0.rank < $1.rank } == [.low, .medium, .high])
    }

    /// Le NAS n'attribue aucun identifiant, et deux alertes peuvent partager tous leurs champs.
    @Test func distinguishesTwoIdenticalAlerts() throws {
        let payload = Data(#"""
        {"total":2,"items":[
          {"create_time":"2026/07/27 18:41:49","severity":"high","user":"testeur",
           "str_id":"abnormal_login","str_section":"loganalyzer","str_args":{}},
          {"create_time":"2026/07/27 18:41:49","severity":"high","user":"testeur",
           "str_id":"abnormal_login","str_section":"loganalyzer","str_args":{}}]}
        """#.utf8)

        let events = try JSONDecoder().decode(LoginActivityPage.self, from: payload).events

        #expect(events[0].id != events[1].id)
    }

    /// Une réponse sans arguments ne doit pas faire échouer la lecture : l'alerte reste
    /// listée, seule sa phrase perd ses précisions.
    @Test func survivesAnEventWithoutArguments() throws {
        let payload = Data(#"""
        {"total":1,"items":[{"create_time":"2026/07/27 18:41:49","severity":"medium",
          "str_id":"brute_force_attack","str_section":"loganalyzer"}]}
        """#.utf8)

        let event = try #require(
            try JSONDecoder().decode(LoginActivityPage.self, from: payload).events.first
        )

        #expect(event.kind == .bruteForceAttack)
        #expect(event.details == .empty)
    }
}
