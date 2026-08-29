import Foundation
import Testing
@testable import dsmaccess

@MainActor
struct DSMFileServiceSettingsServiceTests {
    /// One `get` fills both groups: DSM returns a single flat object and the app splits it
    /// only because there are two `set` calls.
    @Test func readsBothSettingGroupsFromOneResponse() async throws {
        let stub = DSMRequestStub(results: [.response(Self.getResponse)])
        let service = makeService(stub: stub)

        let settings = try await service.smbSettings()

        #expect(settings.basic.isEnabled)
        #expect(settings.basic.workgroup == "WORKGROUP")
        #expect(settings.basic.deniesPreviousVersions == false)
        #expect(settings.basic.hidesUnauthorizedShares == false)
        #expect(settings.advanced.winsServer.isEmpty)
        #expect(settings.advanced.durableHandles)
        #expect(settings.advanced.symbolicLinks)
        #expect(settings.advanced.directorySorting == false)
    }

    /// ⚠️ The numbers DSM uses are not version numbers: `smb_min_protocol` 1 means SMB2, and
    /// `enable_server_signing` 0 does not mean "off" but "SMB1 signing only". Reading them as
    /// booleans or as versions would silently change what the NAS negotiates.
    @Test func decodesTheEnumeratedFieldsByTheirMeasuredNumbers() async throws {
        let stub = DSMRequestStub(results: [.response(Self.getResponse)])
        let service = makeService(stub: stub)

        let settings = try await service.smbSettings()

        #expect(settings.advanced.minimumProtocol == .smb2)
        #expect(settings.advanced.maximumProtocol == .smb3)
        #expect(settings.advanced.transportEncryption == .clientDefined)
        #expect(settings.advanced.serverSigning == .smb1Only)
    }

    /// Contract measured on DSM 7.4: applying the main screen sends five fields and no more.
    /// ⚠️ One of them, `smb_transfer_log_enable`, does not exist in the `get` at all.
    @Test func sendsTheFiveFieldsTheMainScreenApplies() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.setSMBBasicSettings(
            SMBBasicSettings(
                isEnabled: true,
                workgroup: "ATELIER",
                deniesPreviousVersions: true,
                hidesUnauthorizedShares: false
            ),
            logsTransfers: true
        )

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["api"] == "SYNO.Core.FileServ.SMB")
        #expect(parameters["method"] == "set")
        #expect(parameters["enable_samba"] == "true")
        #expect(parameters["workgroup"] == "\"ATELIER\"")
        #expect(parameters["disable_shadow_copy"] == "true")
        #expect(parameters["enable_access_based_share_enum"] == "false")
        #expect(parameters["smb_transfer_log_enable"] == "true")
        // No advanced field rides along: mixing the two calls was never measured.
        #expect(parameters["enable_dirsort"] == nil)
        #expect(parameters["smb_min_protocol"] == nil)
    }

    /// The advanced dialog sends its twenty-nine fields together, `enable_samba` included.
    /// Sending a subset was never measured, and DSM's own client never does it.
    @Test func sendsEveryAdvancedFieldTogether() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        try await service.setSMBAdvancedSettings(Self.advancedSample, isEnabled: true)

        let parameters = try query(from: try #require(await stub.requests.first))
        let sent = Set(parameters.keys).subtracting(["api", "method", "version", "_sid"])
        #expect(sent.count == 29)
        #expect(parameters["enable_samba"] == "true")
        #expect(parameters["smb_max_protocol"] == "3")
        #expect(parameters["smb_min_protocol"] == "1")
        #expect(parameters["smb_encrypt_transport"] == "1")
        #expect(parameters["enable_server_signing"] == "0")
        #expect(parameters["wins"] == "\"\"")
        #expect(parameters["enable_perf_chart"] == "false")
    }

    /// The veto fields are carried without being editable: the measured call sends them on
    /// every save, so dropping them would clear a configuration the screen cannot yet show.
    @Test func carriesTheVetoFieldsItCannotEditYet() async throws {
        let stub = DSMRequestStub(results: [.response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)
        var settings = Self.advancedSample
        settings.vetoesFiles = true
        settings.deletesDirectoriesHoldingVetoedFiles = true

        try await service.setSMBAdvancedSettings(settings, isEnabled: true)

        let parameters = try query(from: try #require(await stub.requests.first))
        #expect(parameters["enable_vetofile"] == "true")
        #expect(parameters["enable_delete_vetofiles"] == "true")
    }

    /// Applying settings is a mutation: a timeout must not replay it. The NAS may have
    /// applied them and restarted Samba before answering.
    @Test func neverReplaysAnApplyAfterATimeout() async throws {
        let stub = DSMRequestStub(results: [.timeout, .response(Data(#"{"success":true}"#.utf8))])
        let service = makeService(stub: stub)

        do {
            try await service.setSMBAdvancedSettings(Self.advancedSample, isEnabled: true)
            Issue.record("L’application aurait dû échouer après le délai d’attente.")
        } catch {
            let dsmError = try #require(error as? DSMError)
            guard case .network = dsmError else {
                Issue.record("Erreur inattendue : \(dsmError)")
                return
            }
        }
        #expect(await stub.requestCount == 1)
    }

    /// A refusal must surface: presenting it as a success would leave the screen showing
    /// settings the NAS never accepted.
    @Test func reportsSettingsRefusedByTheNAS() async throws {
        let stub = DSMRequestStub(results: [
            .response(Data(#"{"success":false,"error":{"code":120}}"#.utf8)),
        ])
        let service = makeService(stub: stub)

        await #expect(throws: DSMError.self) {
            try await service.setSMBBasicSettings(
                SMBBasicSettings(
                    isEnabled: true,
                    workgroup: "WORKGROUP",
                    deniesPreviousVersions: false,
                    hidesUnauthorizedShares: false
                ),
                logsTransfers: false
            )
        }
    }

    // MARK: - Fixtures

    /// Shape captured on the development DS920+ (DSM 7.4). Values are the NAS defaults, with
    /// nothing identifying the server.
    private static let getResponse = Data(#"""
    {"success":true,"data":{
      "disable_shadow_copy":false,"disable_strict_allocate":false,
      "enable_access_based_share_enum":false,"enable_adserver":null,"enable_aio_read":false,
      "enable_delete_vetofiles":false,"enable_dirsort":false,"enable_durable_handles":true,
      "enable_enhance_log":false,"enable_fruit_locking":false,"enable_kerberos":false,
      "enable_local_master_browser":false,"enable_mask":false,"enable_msdfs":false,
      "enable_multichannel":false,"enable_ntlmv1_auth":false,"enable_op_lock":true,
      "enable_perf_chart":false,"enable_reset_on_zero_vc":false,"enable_samba":true,
      "enable_server_signing":0,"enable_smb2_leases":true,
      "enable_smb3_directory_leasing":false,"enable_strict_sync":false,"enable_symlink":true,
      "enable_syno_catia":true,"enable_synotify":true,"enable_vetofile":false,
      "enable_widelink":false,"offline_files_support":false,"smb_encrypt_transport":1,
      "smb_max_protocol":3,"smb_min_protocol":1,"syno_wildcard_search":false,
      "vetofile":"","wins":"","workgroup":"WORKGROUP"
    }}
    """#.utf8)

    private static let advancedSample = SMBAdvancedSettings(
        winsServer: "",
        maximumProtocol: .smb3,
        minimumProtocol: .smb2,
        transportEncryption: .clientDefined,
        serverSigning: .smb1Only,
        opportunisticLocking: true,
        smb2FileLeases: true,
        smb3DirectoryLeasing: false,
        durableHandles: true,
        macCharacterConversion: true,
        crossProtocolLockingWithAFP: false,
        localMasterBrowser: false,
        directorySorting: false,
        vetoesFiles: false,
        deletesDirectoriesHoldingVetoedFiles: false,
        symbolicLinks: true,
        wideLinks: false,
        resetsOnZeroVirtualCircuit: false,
        debugLogging: false,
        defaultUnixPermissions: false,
        skipsDiskAllocation: false,
        ntlmv1Authentication: false,
        asynchronousRead: false,
        subfolderChangeNotification: true,
        immediateSync: false,
        smb3Multichannel: false,
        wildcardSearchCache: false,
        performanceAnalysis: false
    )

    private func makeService(stub: DSMRequestStub) -> DSMFileServiceSettingsService {
        var capabilities = DSMCapabilities()
        capabilities.merge([
            "SYNO.Core.FileServ.SMB": APIInfoEntry(
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: 3,
                requestFormat: "JSON"
            ),
        ])
        let transport = DSMTransport(
            endpoint: DSMEndpoint(useHTTPS: true, host: "nas.local", port: 5001),
            session: .shared,
            capabilities: capabilities,
            requestData: { try await stub.data(for: $0) }
        )
        transport.establishSession(LoginResult(sid: "session-id", did: nil, synotoken: nil))
        return DSMFileServiceSettingsService(transport: transport)
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
