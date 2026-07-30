//
//  DSMLogSecurityService.swift
//  dsmaccess
//
//  NAS system log and the auto-block block list.
//

import Foundation

@MainActor
final class DSMLogSecurityService {
    private static let logAPI = DSMAPI("SYNO.Core.SyslogClient.Log")
    private static let blockListAPI = DSMAPI("SYNO.Core.Security.AutoBlock.Rules")
    private static let transferLoggingAPI = DSMAPI("SYNO.Core.SyslogClient.FileTransfer")
    private static let loginActivityAPI = DSMAPI("SYNO.SecurityAdvisor.LoginActivity")
    /// ⚠️ This API carries the auto-block **settings** and has no `list` method: the address
    /// list lives in `AutoBlock.Rules`.
    private static let autoBlockAPI = DSMAPI("SYNO.Core.Security.AutoBlock")

    private let transport: DSMTransport

    init(transport: DSMTransport) {
        self.transport = transport
    }

    /// A page of the system log. `keyword` is filtered by the NAS itself; the level is not:
    /// verified on DSM 7.4, the `level` parameter is accepted then ignored, so severity
    /// filtering happens app-side.
    ///
    /// ⚠️ `logtype` is essential: without it the NAS only returns the system log, even though
    /// it keeps one log per protocol on top of the connection log. A type the NAS does not
    /// know returns zero entries **without an error** — hence the point of only offering the
    /// logs that are actually active.
    func systemLogs(
        kind: SystemLogKind,
        limit: Int,
        offset: Int = 0,
        keyword: String? = nil
    ) async throws -> SystemLogPage {
        var parameters: [String: DSMParameter] = [
            "logtype": .string(kind.rawValue),
            "offset": .integer(offset),
            "limit": .integer(limit),
            "sort_by": "time",
            "sort_direction": "DESC",
        ]
        if let keyword, !keyword.isEmpty {
            parameters["keyword"] = .string(keyword)
        }
        return try await transport.read(
            api: Self.logAPI,
            method: "list",
            parameters: parameters,
            as: SystemLogPage.self
        )
    }

    /// Writes the requested log to a file produced by the NAS. The export covers the whole
    /// log, not the pages already loaded: 1.9 MB for the development NAS's system log, without
    /// having had to page through it.
    ///
    /// On refusal, DSM returns JSON instead of the file: the content type is what gives it
    /// away, as with File Station downloads.
    ///
    /// ⚠️ The format is requested in **`format`**, not in `type` the way
    /// `SYNO.ResourceMonitor.Log` does. Verified on DSM 7.4: with `type`, the parameter is
    /// ignored without an error and the NAS returns HTML — a file named `.csv` containing HTML.
    func exportSystemLog(
        kind: SystemLogKind,
        format: SystemLogExportFormat,
        to destination: URL
    ) async throws {
        let url = try await transport.makeURL(
            api: Self.logAPI,
            method: "export",
            parameters: [
                "logtype": .string(kind.rawValue),
                "format": .string(format.rawValue),
            ]
        )
        let (temporaryURL, response) = try await transport.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw DSMError.invalidResponse
        }
        if let mimeType = response.mimeType, mimeType.contains("json") {
            let data = try await MultipartBodyFile.readData(at: temporaryURL)
            let decoded = try await DSMTransport.decodeResponse(EmptyData.self, from: data)
            guard !decoded.success else { throw DSMError.invalidResponse }
            throw transport.error(from: decoded.error)
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
    }

    /// Protocols whose transfers are logged. Determines which logs to offer.
    func fileTransferLogging() async throws -> FileTransferLogging {
        try await transport.read(
            api: Self.transferLoggingAPI,
            method: "get",
            as: FileTransferLogging.self
        )
    }

    /// Addresses that auto-block refuses.
    ///
    /// ⚠️ `SYNO.Core.Security.AutoBlock` has **no** `list` method: it only serves the blocking
    /// settings. Calling it earned a 103, reported by a user before being reproduced on the
    /// development NAS. The list lives in `AutoBlock.Rules`, which requires `action` and
    /// `type` — without them, the NAS answers 5100.
    func blockedAddresses(limit: Int) async throws -> BlockedAddressPage {
        try await transport.read(
            api: Self.blockListAPI,
            method: "list",
            parameters: [
                "action": .string("load"),
                "offset": .integer(0),
                "limit": .integer(limit),
                "type": .string(Self.denyList),
            ],
            as: BlockedAddressPage.self
        )
    }

    /// Chooses which protocols have their transfers logged. Enabling a protocol makes its log
    /// appear; turning it off does not remove the entries already recorded.
    ///
    /// The six fields go out together: verified on DSM 7.4, `set` ignores missing fields — a
    /// call with no parameter at all succeeds without changing anything — but sending
    /// everything avoids depending on that behavior.
    ///
    /// Mutation: single-attempt path.
    func setFileTransferLogging(_ logging: FileTransferLogging) async throws {
        let parameters = logging.parameters.mapValues { DSMParameter.boolean($0) }
        try await transport.perform(
            api: Self.transferLoggingAPI,
            method: "set",
            parameters: parameters
        )
    }

    /// Auto-block settings.
    func autoBlockSettings() async throws -> AutoBlockSettings {
        try await transport.read(
            api: Self.autoBlockAPI,
            method: "get",
            as: AutoBlockSettings.self
        )
    }

    /// Mutation: single-attempt path.
    func setAutoBlockSettings(_ settings: AutoBlockSettings) async throws {
        try await transport.perform(
            api: Self.autoBlockAPI,
            method: "set",
            parameters: [
                "enable": .boolean(settings.isEnabled),
                "attempts": .integer(settings.attempts),
                "within_mins": .integer(settings.withinMinutes),
                "expire_day": .integer(settings.expiryDays),
            ]
        )
    }

    /// Sign-in activity recorded by Security Advisor: unusual sign-ins and repeated attempts.
    /// Read-only.
    func loginActivity(limit: Int) async throws -> LoginActivityPage {
        try await transport.read(
            api: Self.loginActivityAPI,
            method: "list",
            parameters: ["offset": .integer(0), "limit": .integer(limit)],
            as: LoginActivityPage.self
        )
    }

    /// Removes addresses from the block list. Mutation: single-attempt path.
    func unblockAddresses(_ addresses: [String]) async throws {
        try await transport.perform(
            api: Self.blockListAPI,
            method: "delete",
            parameters: [
                "type": .string(Self.denyList),
                "ip": try .json(addresses),
            ]
        )
    }

    /// The same API serves the allow list; only the block list is exposed by the app.
    private static let denyList = "deny"
}
