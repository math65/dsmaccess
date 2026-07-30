import Foundation
import Testing
@testable import dsmaccess

/// Shapes captured on DSM 7.4 on 2026/07/30. The values are invented: the addresses, cities
/// and coordinates the NAS actually returns identify people.
@MainActor
struct LoginActivityTests {
    /// A sign-in judged unusual. The NAS supplies no sentence but a key from its catalog and
    /// a bag of arguments: the sentence is written by the app.
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
        // An unusual sign-in carries a single address, in `ip`.
        #expect(event.details.allAddresses == ["192.0.2.10"])
    }

    /// A brute-force attack. Its arguments are not those of an unusual sign-in: the
    /// addresses arrive as a list, with a count and a window.
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
        // No city or single address here: those arguments do not exist for this key.
        #expect(event.details.city == nil)
        #expect(event.details.address == nil)
    }

    /// A key the app cannot word must stay readable and identifiable, so the screen can say
    /// so instead of inventing a sentence.
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

    /// Severities sort by severity, not alphabetically.
    @Test func sortsSeveritiesBySeverity() {
        let severities: [LoginActivityEvent.Severity] = [.high, .low, .medium]

        #expect(severities.sorted { $0.rank < $1.rank } == [.low, .medium, .high])
    }

    /// The NAS assigns no identifier, and two alerts can share every one of their fields.
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

    /// A response without arguments must not fail the read: the alert stays listed, only its
    /// sentence loses its details.
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
