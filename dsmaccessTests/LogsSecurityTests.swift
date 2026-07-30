import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct LogsSecurityTests {
    /// Forme réelle d'une page de journal, relevée sur le DS920+ en DSM 7.4. La racine est
    /// `items`, et le NAS joint le décompte par gravité à chaque page.
    @Test func readsALogPageWithItsSeverityCounts() throws {
        let payload = Data(#"""
        {"errorCount":83,"infoCount":911,"warnCount":6,"total":6995,
         "items":[
           {"descr":"Le systeme a demarre","level":"info","logtype":"Système",
            "orginalLogType":"system","time":"2026/07/30 09:00:00","who":""},
           {"descr":"Echec de connexion","level":"err","logtype":"Système",
            "orginalLogType":"system","time":"2026/07/30 09:05:12","who":"testeur"}]}
        """#.utf8)

        let page = try JSONDecoder().decode(SystemLogPage.self, from: payload)

        #expect(page.total == 6995)
        #expect(page.errorCount == 83)
        #expect(page.warningCount == 6)
        #expect(page.infoCount == 911)
        #expect(page.entries.count == 2)
        #expect(page.entries[0].level == .info)
        #expect(page.entries[1].level == .error)
        // Un compte vide vaut absence : la colonne affiche un tiret plutôt qu'un blanc.
        #expect(page.entries[0].account == nil)
        #expect(page.entries[1].account == "testeur")
    }

    /// DSM code la gravité en trois valeurs courtes. Une quatrième serait une évolution de DSM,
    /// conservée telle quelle plutôt que rangée d'office dans un niveau existant.
    @Test func mapsTheThreeLevelsDSMCodes() {
        #expect(SystemLogEntry.Level(rawValue: "info") == .info)
        #expect(SystemLogEntry.Level(rawValue: "warn") == .warning)
        #expect(SystemLogEntry.Level(rawValue: "err") == .error)
        #expect(SystemLogEntry.Level(rawValue: "emerg") == .other("emerg"))
    }

    /// La colonne Niveau se trie par gravité : classer « Erreur » avant « Information » parce
    /// que E précède I n'aurait aucun sens à la lecture.
    @Test func sortsLevelsBySeverityAndNotAlphabetically() {
        let levels: [SystemLogEntry.Level] = [.error, .info, .warning]

        #expect(levels.sorted { $0.severity < $1.severity } == [.info, .warning, .error])
    }

    /// Le NAS n'attribue aucun identifiant, et deux entrées peuvent partager la seconde, le
    /// niveau et le message. Sans identité distincte, le tableau confondrait les lignes.
    @Test func distinguishesTwoIdenticalEntriesInTheSameSecond() throws {
        let payload = Data(#"""
        {"items":[
          {"descr":"identique","level":"info","time":"2026/07/30 09:00:00"},
          {"descr":"identique","level":"info","time":"2026/07/30 09:00:00"}],"total":2}
        """#.utf8)

        let entries = try JSONDecoder().decode(SystemLogPage.self, from: payload).entries

        #expect(entries[0].id != entries[1].id)
    }

    /// Contrat de la liste de blocage, éprouvé en ajoutant puis retirant une adresse réservée à
    /// la documentation. Les horodatages arrivent en secondes Unix.
    @Test func readsABlockedAddressAsTheNASSendsIt() throws {
        let payload = Data(#"""
        {"ip_info":[{"country":"","expire_date":0,"expire_formated_date":"1970/01/01 01:00:00",
          "ip":"192.0.2.7","is_public_ip":true,"record_date":1785403952,
          "record_formated_date":"2026/07/30 11:32:32"}],"offset":0,"total":1}
        """#.utf8)

        let page = try JSONDecoder().decode(BlockedAddressPage.self, from: payload)
        let address = try #require(page.addresses.first)

        #expect(page.total == 1)
        #expect(address.address == "192.0.2.7")
        #expect(address.isPublic)
        #expect(address.blockedAt == Date(timeIntervalSince1970: 1_785_403_952))
        // Un pays vide vaut absence, pas une chaîne à afficher.
        #expect(address.country == nil)
    }

    /// ⚠️ Le piège de cette API : `expire_date` à zéro signifie « définitivement », et le NAS
    /// formate quand même sa date à 1970. Lue telle quelle, une adresse bloquée pour toujours
    /// se présenterait comme expirée depuis un demi-siècle.
    @Test func readsAZeroExpiryAsNoExpiryAtAll() throws {
        let payload = Data(#"""
        {"ip_info":[
          {"ip":"192.0.2.7","expire_date":0,"expire_formated_date":"1970/01/01 01:00:00",
           "record_date":1785403952,"is_public_ip":true},
          {"ip":"192.0.2.8","expire_date":1785490352,"record_date":1785403952,
           "is_public_ip":true}],"total":2}
        """#.utf8)

        let addresses = try JSONDecoder().decode(BlockedAddressPage.self, from: payload).addresses

        #expect(addresses[0].expiresAt == nil)
        #expect(addresses[1].expiresAt == Date(timeIntervalSince1970: 1_785_490_352))
        // Un blocage sans expiration se range après ceux qui expirent : il est le plus durable.
        #expect(addresses[0].sortableExpiry > addresses[1].sortableExpiry)
    }

    /// Sans adresse, la ligne ne peut être ni affichée ni débloquée : le décodage échoue plutôt
    /// que de produire une entrée sur laquelle aucune action ne marchera.
    @Test func refusesABlockedAddressWithoutAnAddress() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                BlockedAddressPage.self,
                from: Data(#"{"ip_info":[{"record_date":1785403952}],"total":1}"#.utf8)
            )
        }
    }

    /// Une liste vide est le cas courant d'un NAS sain, et non une anomalie.
    @Test func survivesAnEmptyBlockList() throws {
        let page = try JSONDecoder().decode(
            BlockedAddressPage.self, from: Data(#"{"ip_info":[],"offset":0,"total":0}"#.utf8)
        )

        #expect(page.addresses.isEmpty)
        #expect(page.total == 0)
    }

    // MARK: - Requêtes

    /// ⚠️ Le bug signalé par un utilisateur en beta.16 : la liste de blocage était demandée à
    /// `SYNO.Core.Security.AutoBlock`, qui n'a pas de méthode `list` et répond 103. La liste
    /// vit dans `AutoBlock.Rules`, qui exige `action` et `type` — sans eux, le NAS répond 5100.
    @Test func asksTheAPIThatActuallyHoldsTheBlockList() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"ip_info":[],"offset":0,"total":0}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        _ = try await service.blockedAddresses(limit: 500)

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Core.Security.AutoBlock.Rules")
        #expect(parameters["method"] == "list")
        #expect(parameters["action"] == "\"load\"")
        #expect(parameters["type"] == "\"deny\"")
    }

    /// Le mot-clé part au NAS, qui cherche dans tout le journal et non dans la seule page
    /// chargée. Absent, il ne doit pas être envoyé vide.
    @Test func sendsTheSearchKeywordToTheNAS() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"items":[],"total":0}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"items":[],"total":0}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        _ = try await service.systemLogs(limit: 1000, keyword: "connexion")
        _ = try await service.systemLogs(limit: 1000, keyword: "")

        let requests = await stub.requests
        let searched = try query(from: requests[0])
        #expect(searched["api"] == "SYNO.Core.SyslogClient.Log")
        #expect(searched["keyword"] == "\"connexion\"")
        #expect(searched["limit"] == "1000")
        #expect(try query(from: requests[1])["keyword"] == nil)
    }

    /// Débloquer est une mutation : un délai d'attente ne doit pas la rejouer. Le NAS peut
    /// avoir retiré l'adresse avant de répondre, et le blocage automatique peut l'avoir
    /// rebloquée entre-temps.
    @Test func neverReplaysAnUnblockAfterATimeout() async throws {
        let stub = DSMRequestStub(results: [.timeout, .response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        do {
            try await service.unblockAddresses(["192.0.2.7"])
            Issue.record("Le déblocage aurait dû échouer après le délai d’attente.")
        } catch {
            let dsmError = try #require(error as? DSMError)
            guard case .network = dsmError else {
                Issue.record("Erreur inattendue : \(dsmError)")
                return
            }
        }
        #expect(await stub.requestCount == 1)
    }

    /// Le NAS attend une liste d'adresses, même pour une seule.
    @Test func unblocksAddressesAsAList() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.unblockAddresses(["192.0.2.7", "192.0.2.8"])

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["method"] == "delete")
        #expect(parameters["type"] == "\"deny\"")
        let addresses = try JSONDecoder().decode(
            [String].self, from: Data(try #require(parameters["ip"]).utf8)
        )
        #expect(addresses == ["192.0.2.7", "192.0.2.8"])
    }

    private func makeService(stub: DSMRequestStub) -> DSMLogSecurityService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Core.SyslogClient.Log": APIInfoEntry(
                path: "entry.cgi", minVersion: 1, maxVersion: 1, requestFormat: "JSON"
            ),
            "SYNO.Core.Security.AutoBlock.Rules": APIInfoEntry(
                path: "entry.cgi", minVersion: 1, maxVersion: 1, requestFormat: "JSON"
            ),
        ])
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) }
        )
        transport.establishSession(LoginResult(sid: "session-id", did: nil, synotoken: nil))
        return DSMLogSecurityService(transport: transport)
    }

    private func query(from request: URLRequest) throws -> [String: String] {
        let url = try #require(request.url)
        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        )
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
