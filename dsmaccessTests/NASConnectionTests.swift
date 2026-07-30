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

    /// `kick_connection` réidentifie la session par un quadruplet qui dépend du protocole.
    /// Une session web est reconnue par sa valeur exacte « HTTP/HTTPS » : la confondre avec un
    /// « HTTP » nu enverrait toutes les sessions web dans la liste des autres protocoles.
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

    /// Le NAS refuse la coupure de certaines sessions. Sans référence, l'app ne peut pas
    /// proposer une action qui échouerait, ni en viser une autre à la place.
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
        // Protocole hors web sans `pid` : rien ne permet de désigner la session.
        #expect(items[1].kickReference == nil)
    }

    /// Plusieurs sessions web du même compte partagent compte, adresse, protocole et
    /// horodatage. Sans le jeton d'appareil dans la clé, elles se confondraient et une
    /// sélection porterait sur la mauvaise.
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
