import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct LogsSecurityTests {
    /// Actual shape of a log page, captured on the DS920+ running DSM 7.4. The root is
    /// `items`, and the NAS attaches the per-severity counts to every page.
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
        // An empty account means absence: the column shows a dash rather than a blank.
        #expect(page.entries[0].account == nil)
        #expect(page.entries[1].account == "testeur")
    }

    /// DSM encodes severity as three short values. A fourth one would be a DSM change, kept
    /// as-is rather than forced into an existing level.
    @Test func mapsTheThreeLevelsDSMCodes() {
        #expect(SystemLogEntry.Level(rawValue: "info") == .info)
        #expect(SystemLogEntry.Level(rawValue: "warn") == .warning)
        #expect(SystemLogEntry.Level(rawValue: "err") == .error)
        #expect(SystemLogEntry.Level(rawValue: "emerg") == .other("emerg"))
    }

    /// The Level column sorts by severity: ordering "Error" before "Information" because E
    /// comes before I would make no sense to read.
    @Test func sortsLevelsBySeverityAndNotAlphabetically() {
        let levels: [SystemLogEntry.Level] = [.error, .info, .warning]

        #expect(levels.sorted { $0.severity < $1.severity } == [.info, .warning, .error])
    }

    /// The NAS assigns no identifier, and two entries can share the same second, level and
    /// message. Without a distinct identity, the table would conflate the rows.
    @Test func distinguishesTwoIdenticalEntriesInTheSameSecond() throws {
        let payload = Data(#"""
        {"items":[
          {"descr":"identique","level":"info","time":"2026/07/30 09:00:00"},
          {"descr":"identique","level":"info","time":"2026/07/30 09:00:00"}],"total":2}
        """#.utf8)

        let entries = try JSONDecoder().decode(SystemLogPage.self, from: payload).entries

        #expect(entries[0].id != entries[1].id)
    }

    /// Block list contract, proven by adding then removing a documentation-reserved address.
    /// Timestamps arrive as Unix seconds.
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
        // An empty country means absence, not a string to display.
        #expect(address.country == nil)
    }

    /// ⚠️ The trap in this API: `expire_date` set to zero means "permanently", and the NAS
    /// still formats its date as 1970. Taken at face value, an address blocked forever would
    /// look like it expired half a century ago.
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
        // A block with no expiry sorts after those that expire: it is the longest-lasting one.
        #expect(addresses[0].sortableExpiry > addresses[1].sortableExpiry)
    }

    /// Without an address, the row can neither be displayed nor unblocked: decoding fails
    /// rather than producing an entry no action will work on.
    @Test func refusesABlockedAddressWithoutAnAddress() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                BlockedAddressPage.self,
                from: Data(#"{"ip_info":[{"record_date":1785403952}],"total":1}"#.utf8)
            )
        }
    }

    /// An empty list is the normal case on a healthy NAS, not an anomaly.
    @Test func survivesAnEmptyBlockList() throws {
        let page = try JSONDecoder().decode(
            BlockedAddressPage.self, from: Data(#"{"ip_info":[],"offset":0,"total":0}"#.utf8)
        )

        #expect(page.addresses.isEmpty)
        #expect(page.total == 0)
    }

    // MARK: - Requests

    /// ⚠️ The bug a user reported in beta.16: the block list was requested from
    /// `SYNO.Core.Security.AutoBlock`, which has no `list` method and answers 103. The list
    /// lives in `AutoBlock.Rules`, which requires `action` and `type` — without them, the NAS
    /// answers 5100.
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

    /// The keyword goes to the NAS, which searches the whole log and not just the loaded
    /// page. When there is none, it must not be sent empty.
    @Test func sendsTheSearchKeywordToTheNAS() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"items":[],"total":0}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"items":[],"total":0}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        _ = try await service.systemLogs(kind: .system, limit: 1000, keyword: "connexion")
        _ = try await service.systemLogs(kind: .system, limit: 1000, keyword: "")

        let requests = await stub.requests
        let searched = try query(from: requests[0])
        #expect(searched["api"] == "SYNO.Core.SyslogClient.Log")
        #expect(searched["keyword"] == "\"connexion\"")
        #expect(searched["limit"] == "1000")
        #expect(try query(from: requests[1])["keyword"] == nil)
    }

    /// ⚠️ Without `logtype`, the NAS only returns the system log: on the development NAS,
    /// 6,997 system entries against more than 114,000 in total. The type must therefore
    /// always be sent, in the form the NAS expects — transfer logs are named after their
    /// protocol.
    @Test func alwaysNamesTheLogItAsksFor() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"items":[],"total":0}}"#.utf8)),
            .response(Data(#"{"success":true,"data":{"items":[],"total":0}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        _ = try await service.systemLogs(kind: .connection, limit: 10)
        _ = try await service.systemLogs(kind: .fileStation, limit: 10)

        let requests = await stub.requests
        #expect(try query(from: requests[0])["logtype"] == "\"connection\"")
        // "filestation" is the NAS's value, which Swift casing must not distort.
        #expect(try query(from: requests[1])["logtype"] == "\"filestation\"")
    }

    /// Transfer logs only exist for protocols whose logging is enabled. A disabled log would
    /// return zero entries without an error, which would read as an empty log: it must not be
    /// offered.
    @Test func readsWhichTransferLogsTheNASKeeps() throws {
        let payload = Data(#"""
        {"afp":false,"cifs":true,"filestation":true,"ftp":false,"tftp":false,"webdav":false}
        """#.utf8)

        let logging = try JSONDecoder().decode(FileTransferLogging.self, from: payload)

        #expect(logging.enabled == [.cifs, .fileStation])
        let offered = SystemLogKind.always + SystemLogKind.transfers.filter(logging.enabled.contains)
        #expect(offered == [.system, .connection, .cifs, .fileStation])
    }

    /// A transfer log does not have the same shape: no severity, but the originating address,
    /// the operation and the size. Shape captured from the DS920+'s SMB log.
    @Test func readsATransferEntryWithItsOwnFields() throws {
        let payload = Data(#"""
        {"errorCount":0,"infoCount":0,"warnCount":0,"total":81420,
         "items":[{"cmd":"read","descr":"/tmmac/sauvegarde.sparsebundle/token","filesize":32,
           "ip":"192.168.1.20","isdir":false,"logtype":"SMB","orginalLogType":"cifs",
           "time":"2026/07/30 08:24:59","username":"testeur"}]}
        """#.utf8)

        let entry = try #require(
            try JSONDecoder().decode(SystemLogPage.self, from: payload).entries.first
        )

        // No severity: inventing one would be a misreading.
        #expect(entry.level == nil)
        #expect(entry.sortableLevel == -1)
        // The account is read from `username` here, and from `who` elsewhere.
        #expect(entry.account == "testeur")
        #expect(entry.address == "192.168.1.20")
        #expect(entry.operation == "read")
        #expect(entry.fileSize == 32)
        #expect(!entry.isDirectory)
        #expect(SystemLogKind.cifs.isTransfer)
        #expect(!SystemLogKind.system.isTransfer)
    }

    /// A folder has no useful size, and the NAS writes zero there: showing it as "zero bytes"
    /// would make a folder look like an empty file.
    @Test func treatsAFolderAsHavingNoSize() throws {
        let payload = Data(#"""
        {"items":[{"cmd":"mkdir","descr":"/tmmac/dossier","filesize":0,"isdir":true,
          "time":"2026/07/30 08:24:59","username":"testeur"}],"total":1}
        """#.utf8)

        let entry = try #require(
            try JSONDecoder().decode(SystemLogPage.self, from: payload).entries.first
        )

        #expect(entry.isDirectory)
        #expect(entry.fileSize == nil)
    }

    /// The next slice is requested by offset. Without shifting the identifiers, the second
    /// page would carry those of the first and the table would conflate its rows.
    @Test func numbersTheNextSliceAfterTheOneAlreadyShown() throws {
        let payload = Data(#"""
        {"items":[{"descr":"a","level":"info","time":"2026/07/30 09:00:00"},
                  {"descr":"b","level":"info","time":"2026/07/30 09:00:01"}],"total":4}
        """#.utf8)
        let page = try JSONDecoder().decode(SystemLogPage.self, from: payload)

        let firstSlice = page.entries
        let secondSlice = page.entries.map { $0.renumbered(from: firstSlice.count) }

        #expect(firstSlice.map(\.id) == [0, 1])
        #expect(secondSlice.map(\.id) == [2, 3])
        #expect(Set((firstSlice + secondSlice).map(\.id)).count == 4)
    }

    /// The requested offset must follow what is already displayed, and the search must stay
    /// attached to the slice: without it, the continuation would cover an unfiltered log.
    @Test func asksForTheNextSliceAtTheRightOffset() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true,"data":{"items":[],"total":6995}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        _ = try await service.systemLogs(
            kind: .system,
            limit: 1000,
            offset: 1000,
            keyword: "connexion"
        )

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["offset"] == "1000")
        #expect(parameters["limit"] == "1000")
        #expect(parameters["keyword"] == "\"connexion\"")
    }

    /// The export covers the chosen log, not the system log by default: without `logtype`, a
    /// user browsing SMB transfers would receive the system log.
    @Test func exportsTheLogCurrentlyBeingRead() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-test-\(UUID().uuidString).csv")
        // The NAS returns a file, not JSON: the content type is what tells a successful export
        // from a refusal.
        let stub = DSMRequestStub(results: [
            .HTTPResponse(
                data: Data("heure,niveau\n".utf8),
                statusCode: 200,
                contentType: "text/csv"
            ),
        ])
        let service = makeService(stub: stub)

        try await service.exportSystemLog(kind: .cifs, format: .csv, to: destination)

        #expect(FileManager.default.fileExists(atPath: destination.path))

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Core.SyslogClient.Log")
        #expect(parameters["method"] == "export")
        #expect(parameters["logtype"] == "\"cifs\"")
        // ⚠️ "format" and not "type": with `type`, the NAS ignores the request without an error
        // and returns HTML. A file named .csv containing HTML got through review once.
        #expect(parameters["format"] == "\"csv\"")
        #expect(parameters["type"] == nil)
        try? FileManager.default.removeItem(at: destination)
    }

    /// All six protocols are sent together, including those at their current value. Verified
    /// on the NAS: `set` ignores missing fields — a call with no parameter at all succeeds
    /// without changing anything — but sending everything avoids relying on that behavior.
    @Test func sendsEveryTransferProtocolWhenSavingLogging() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.setFileTransferLogging(
            FileTransferLogging(enabled: [.cifs, .fileStation])
        )

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Core.SyslogClient.FileTransfer")
        #expect(parameters["method"] == "set")
        #expect(parameters["cifs"] == "true")
        #expect(parameters["filestation"] == "true")
        #expect(parameters["afp"] == "false")
        #expect(parameters["ftp"] == "false")
        #expect(parameters["tftp"] == "false")
        #expect(parameters["webdav"] == "false")
    }

    /// ⚠️ Zero days means "no expiry" and not "expires today". The setting must survive a read
    /// and a write without that zero turning into a date.
    @Test func readsAndWritesAutoBlockSettingsIncludingTheZeroExpiry() async throws {
        let decoded = try JSONDecoder().decode(
            AutoBlockSettings.self,
            from: Data(#"{"attempts":10,"enable":true,"expire_day":0,"within_mins":5}"#.utf8)
        )

        #expect(decoded.isEnabled)
        #expect(decoded.attempts == 10)
        #expect(decoded.withinMinutes == 5)
        #expect(decoded.expiryDays == 0)
        #expect(!decoded.expires)

        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":true}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        try await service.setAutoBlockSettings(decoded)

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Core.Security.AutoBlock")
        #expect(parameters["method"] == "set")
        #expect(parameters["enable"] == "true")
        #expect(parameters["attempts"] == "10")
        #expect(parameters["within_mins"] == "5")
        #expect(parameters["expire_day"] == "0")
    }

    /// Unblocking is a mutation: a timeout must not replay it. The NAS may have removed the
    /// address before answering, and auto-block may have re-blocked it in the meantime.
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

    /// The NAS expects a list of addresses, even for a single one.
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
            "SYNO.Core.Security.AutoBlock": APIInfoEntry(
                path: "entry.cgi", minVersion: 1, maxVersion: 1, requestFormat: "JSON"
            ),
            "SYNO.Core.SyslogClient.FileTransfer": APIInfoEntry(
                path: "entry.cgi", minVersion: 1, maxVersion: 1, requestFormat: "JSON"
            ),
        ])
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) },
            downloadFile: { try await stub.download(from: $0) }
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
