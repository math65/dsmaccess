import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct NASConnectionTests {
    /// Shape captured on DSM 7.4 on 2026/07/29. Accounts and addresses are replaced: a
    /// fixture must carry nothing from the real NAS.
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

    /// The timestamp arrives in the NAS format, which is no locale's: it must be converted
    /// to be presented in the user's language.
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

    /// `kick_connection` re-identifies the session by a four-part key that depends on the
    /// protocol. A web session is recognized by its exact value "HTTP/HTTPS": mistaking it
    /// for a bare "HTTP" would send every web session into the other-protocols list.
    @Test func buildsTheKickReferenceExpectedForEachProtocol() throws {
        let items = try JSONDecoder().decode(NASConnectionPage.self, from: payload).items

        #expect(items[0].isWebSession)
        #expect(
            items[0].kickReference
                == .web(deviceID: "", account: "testeur", resource: "DiskStation Manager", address: "10.0.0.2")
        )
        #expect(!items[1].isWebSession)
        #expect(
            items[1].kickReference
                == .service(processID: 2, type: "SMB3", account: "testeur", address: "10.0.0.2")
        )
    }

    /// The NAS refuses to cut some sessions. Without a reference, the app can neither offer
    /// an action that would fail, nor target another one instead.
    @Test func refusesToReferenceASessionTheNASProtects() throws {
        let payload = Data(#"""
        {"items":[
          {"who":"testeur","from":"10.0.0.2","type":"SMB3","descr":"home","pid":2,
           "time":"2026/07/29 11:38:17","can_be_kicked":false},
          {"who":"testeur","from":"10.0.0.2","type":"FTP","descr":"home",
           "time":"2026/07/29 11:38:17","can_be_kicked":true}]}
        """#.utf8)

        let items = try JSONDecoder().decode(NASConnectionPage.self, from: payload).items

        #expect(items[0].kickReference == nil)
        // Non-web protocol without `pid`: nothing lets us designate the session.
        #expect(items[1].kickReference == nil)
    }

    /// Several web sessions of the same account share account, address, protocol and
    /// timestamp. Without the device token in the key, they would collide and a selection
    /// would land on the wrong one.
    @Test func distinguishesTwoWebSessionsOfTheSameAccount() throws {
        let payload = Data(#"""
        {"items":[
          {"who":"testeur","from":"10.0.0.2","type":"HTTP/HTTPS","descr":"DiskStation Manager",
           "did":"jeton-a","pid":1,"time":"2026/07/29 18:02:31","can_be_kicked":true},
          {"who":"testeur","from":"10.0.0.2","type":"HTTP/HTTPS","descr":"DiskStation Manager",
           "did":"jeton-b","pid":1,"time":"2026/07/29 18:02:31","can_be_kicked":true}]}
        """#.utf8)

        let items = try JSONDecoder().decode(NASConnectionPage.self, from: payload).items

        #expect(items[0].id != items[1].id)
    }

    /// A timestamp DSM would send in another shape must not take the row down with it: the
    /// connection stays listed, without a date.
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
