import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct NASConnectionTests {
    /// Forme relevée sur DSM 7.4 le 29/07/2026. Les comptes et adresses sont remplacés :
    /// une fixture ne doit rien porter du NAS réel.
    private let payload = Data(#"""
    {"total":2,"systime":"Wed Jul 29 20:30:00 2026","items":[
      {"can_be_kicked":true,"descr":"DiskStation Manager","did":"","first_login_time":"",
       "from":"10.0.0.2","is_amfa":false,"is_current_connected":false,"is_otp_trusted":false,
       "location":"","pid":1,"protocol":"HTTP/HTTPS","time":"2026/07/29 18:02:31",
       "type":"HTTP/HTTPS","user_agent":"","user_can_be_disabled":true,"who":"testeur"},
      {"can_be_kicked":true,"descr":"Documents, home","did":"","first_login_time":"",
       "from":"10.0.0.2","is_amfa":false,"is_current_connected":true,"is_otp_trusted":false,
       "location":"","pid":2,"protocol":"SMB3","time":"2026/07/29 11:38:17",
       "type":"SMB3","user_agent":"","user_can_be_disabled":true,"who":"testeur"}]}
    """#.utf8)

    @Test func readsWhoConnectedFromWhereAndHow() throws {
        let items = try JSONDecoder().decode(NASConnectionPage.self, from: payload).items

        #expect(items.count == 2)
        let first = try #require(items.first)
        #expect(first.account == "testeur")
        #expect(first.address == "10.0.0.2")
        #expect(first.type == "HTTP/HTTPS")
        #expect(first.descriptionText == "DiskStation Manager")
        #expect(first.canBeKicked)
        #expect(!first.isCurrent)
        #expect(items[1].isCurrent)
    }

    /// L'horodatage arrive au format du NAS, qui n'est celui d'aucune locale : il doit être
    /// converti pour pouvoir être présenté dans la langue de l'utilisateur.
    @Test func parsesTheNASTimestampIntoADate() throws {
        let first = try #require(
            try JSONDecoder().decode(NASConnectionPage.self, from: payload).items.first
        )

        let opened = try #require(first.openedAt)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour], from: opened)
        #expect(parts.year == 2026)
        #expect(parts.month == 7)
        #expect(parts.day == 29)
        #expect(parts.hour == 18)
    }

    /// Un horodatage que DSM enverrait sous une autre forme ne doit pas emporter la ligne :
    /// la connexion reste listée, sans date.
    @Test func keepsAConnectionWhoseTimestampCannotBeRead() throws {
        let payload = Data(#"""
        {"items":[{"who":"testeur","from":"10.0.0.2","type":"SMB3","descr":"home",
          "time":"hier","is_current_connected":false,"can_be_kicked":false}]}
        """#.utf8)

        let connection = try #require(
            try JSONDecoder().decode(NASConnectionPage.self, from: payload).items.first
        )

        #expect(connection.openedAt == nil)
        #expect(connection.account == "testeur")
        #expect(!connection.canBeKicked)
    }
}
