//
//  LogsSecurityViewModel.swift
//  dsmaccess
//
//  NAS system log and the auto-block block list.
//
//  The two reads are independent: a NAS whose block list is denied must still show its log,
//  and the other way round. Each therefore carries its own error.
//

import Foundation
import Observation

@MainActor
@Observable
final class LogsSecurityViewModel {
    /// An active NAS piles up thousands of entries — 6995 on the development DS920+. The page
    /// is large but bounded, and the screen says what it is not showing.
    static let logPageLimit = 1000
    static let blockedPageLimit = 500

    private(set) var logs: [SystemLogEntry] = []
    /// Number of entries kept by the NAS, which often exceeds the loaded page.
    private(set) var totalLogCount = 0
    /// True while the next entries are being fetched, to disarm the button.
    private(set) var isLoadingMore = false
    /// True while the NAS produces the export file.
    private(set) var isExporting = false
    private(set) var blockedAddresses: [BlockedAddress] = []
    private(set) var loginActivity: [LoginActivityEvent] = []
    var loginActivityError: String?
    /// Auto-block settings. `nil` until they have been read: the screen does not present
    /// default values as if they came from the NAS.
    private(set) var autoBlock: AutoBlockSettings?
    var settingsError: String?
    /// True while a setting is being written, to disarm the controls.
    private(set) var isSavingSettings = false
    private(set) var isLoading = false
    /// Addresses currently being unblocked, to disarm their controls.
    private(set) var busyAddresses: Set<String> = []
    var errorMessage: String?
    var blockedAddressesError: String?

    /// Search passed to the NAS, which filters the log itself.
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    /// Selected severity. Filtering is local: verified on DSM 7.4, the NAS accepts a `level`
    /// parameter and then ignores it.
    var levelFilter: LevelFilter = .all

    /// Log being viewed. The NAS keeps one per protocol on top of the system and connection ones.
    private(set) var kind: SystemLogKind = .system
    /// Logs offered: the ones the NAS always keeps, plus the protocols whose transfer logging
    /// is turned on.
    private(set) var availableKinds: [SystemLogKind] = SystemLogKind.always

    enum LevelFilter: Hashable, CaseIterable, Identifiable {
        case all
        case error
        case warning
        case info

        var id: Self { self }
    }

    private let session: SessionStore
    private var loadGeneration = 0
    /// A keystroke must not trigger one request per character.
    private var searchTask: Task<Void, Never>?

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if logs.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }

        await loadAvailableKinds(generation: generation)

        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        do {
            let requested = kind
            let page = try await session.withClient {
                try await $0.systemLogs(
                    kind: requested,
                    limit: Self.logPageLimit,
                    offset: 0,
                    keyword: keyword
                )
            }
            guard generation == loadGeneration else { return }
            logs = page.entries
            totalLogCount = page.total ?? page.entries.count
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }

        await loadBlockedAddresses(generation: generation)
        await loadLoginActivity(generation: generation)
        await loadSettings(generation: generation)

        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: errorMessage == nil ? .result : .error)
        }
    }

    /// Sign-in activity comes from Security Advisor, a different API from the logs: it
    /// therefore carries its own error, so that a denial does not take down the rest of the
    /// screen.
    private func loadLoginActivity(generation: Int) async {
        loginActivityError = nil
        do {
            let page = try await session.withClient {
                try await $0.loginActivity(limit: Self.loginActivityLimit)
            }
            guard generation == loadGeneration else { return }
            loginActivity = page.events.sorted { $0.sortableDate > $1.sortableDate }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            loginActivity = []
            loginActivityError = (error as? DSMError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    static let loginActivityLimit = 200

    /// Settings: transfer logging is already read to populate the log picker; only auto-block
    /// is left to load.
    private func loadSettings(generation: Int) async {
        settingsError = nil
        do {
            let settings = try await session.withClient { try await $0.autoBlockSettings() }
            guard generation == loadGeneration else { return }
            autoBlock = settings
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            autoBlock = nil
            settingsError = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Turns a protocol's logging on or off. The matching log appears in or disappears from
    /// the picker, without losing the entries already recorded.
    func setTransferLogging(_ kind: SystemLogKind, enabled: Bool) async -> DSMOperationOutcome {
        isSavingSettings = true
        defer { isSavingSettings = false }

        var protocols = Set(availableKinds.filter(\.isTransfer))
        if enabled { protocols.insert(kind) } else { protocols.remove(kind) }
        do {
            try await session.withClient {
                try await $0.setFileTransferLogging(FileTransferLogging(enabled: protocols))
            }
            // The picker is rebuilt from the NAS rather than from our own assumption.
            availableKinds = SystemLogKind.always
            await load()
            return .success(
                enabled
                    ? String(localized: "logs.settings.transfer_logging.enabled", defaultValue: "Logging turned on for \(kindText(kind))")
                    : String(localized: "logs.settings.transfer_logging.disabled", defaultValue: "Logging turned off for \(kindText(kind))")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.setting_change_failed", defaultValue: "Could not change the setting: \(reason)"))
        }
    }

    /// Saves the auto-block settings.
    func save(_ settings: AutoBlockSettings) async -> DSMOperationOutcome {
        isSavingSettings = true
        defer { isSavingSettings = false }
        do {
            try await session.withClient { try await $0.setAutoBlockSettings(settings) }
            autoBlock = settings
            return .success(
                settings.isEnabled
                    ? String(localized: "logs.security.autoblock.saved")
                    : String(localized: "logs.security.autoblock.disabled")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.save_failed", defaultValue: "Saving failed: \(reason)"))
        }
    }

    /// Logged protocols, for the settings screen.
    func isTransferLogged(_ kind: SystemLogKind) -> Bool { availableKinds.contains(kind) }

    /// Logs to offer. A transfer log whose protocol is not logged would return zero entries
    /// without an error, which would read as an empty log: better not to offer it. Failing
    /// this read is not a screen error — we then stick to the logs the NAS always keeps.
    private func loadAvailableKinds(generation: Int) async {
        guard availableKinds == SystemLogKind.always else { return }
        let logging = try? await session.withClient { try await $0.fileTransferLogging() }
        guard generation == loadGeneration, let logging else { return }
        availableKinds = SystemLogKind.always
            + SystemLogKind.transfers.filter(logging.enabled.contains)
    }

    /// Switches log. Each log has its own pagination and its own count: the list starts over
    /// from its first page.
    func select(_ kind: SystemLogKind) async {
        guard kind != self.kind else { return }
        self.kind = kind
        logs = []
        totalLogCount = 0
        await load(announce: true)
    }

    /// Appends the log's next page to the one already shown, replacing nothing: the entries
    /// already read stay in place and the table grows.
    ///
    /// The NAS paginates by rank, not by timestamp: if the NAS records a new entry between two
    /// pages, everything shifts by one and an entry can show up twice or slip through the
    /// cracks. DSM has the same limitation. Returns the message to announce, or `nil` if there
    /// was nothing to load.
    func loadMore() async -> DSMOperationOutcome? {
        guard canLoadMore, !isLoadingMore else { return nil }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let generation = loadGeneration
        let offset = logs.count
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        do {
            let requested = kind
            let page = try await session.withClient {
                try await $0.systemLogs(
                    kind: requested,
                    limit: Self.logPageLimit,
                    offset: offset,
                    keyword: keyword
                )
            }
            // A full reload may have started meanwhile: its page is authoritative, not ours.
            guard generation == loadGeneration else { return nil }
            guard !page.entries.isEmpty else {
                // The NAS has nothing left to give: the total it announced was optimistic.
                totalLogCount = logs.count
                return .success(String(localized: "logs.entries.all_shown"))
            }
            logs += page.entries.map { $0.renumbered(from: offset) }
            if let total = page.total { totalLogCount = total }
            return .success(summary)
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "logs.load_more.error", defaultValue: "Could not load the rest: \(reason)"))
        }
    }

    var canLoadMore: Bool { totalLogCount > logs.count }

    /// The block list carries its own error: the log stays readable even if the NAS denies it,
    /// which is what happens for an account without administration privileges.
    private func loadBlockedAddresses(generation: Int) async {
        blockedAddressesError = nil
        do {
            let page = try await session.withClient {
                try await $0.blockedAddresses(limit: Self.blockedPageLimit)
            }
            guard generation == loadGeneration else { return }
            blockedAddresses = page.addresses.sorted {
                $0.sortableBlockedAt > $1.sortableBlockedAt
            }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            blockedAddresses = []
            blockedAddressesError = (error as? DSMError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// The NAS filters the log itself: the search is sent back to it, after a short pause so
    /// the NAS is not queried on every keystroke.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    /// Writes the current log to a file. The export covers the whole log, not the pages
    /// loaded: the NAS produces the file itself.
    func export(as format: SystemLogExportFormat, to destination: URL) async -> DSMOperationOutcome {
        isExporting = true
        defer { isExporting = false }
        let exported = kind
        do {
            try await session.withClient {
                try await $0.exportSystemLog(kind: exported, format: format, to: destination)
            }
            return .success(
                String(localized: "logs.export.success", defaultValue: "Log exported to \(destination.lastPathComponent)")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "logs.export.error", defaultValue: "Could not export: \(reason)"))
        }
    }

    /// Suggested file name: the log and the date, so that two exports do not overwrite each
    /// other in the destination folder.
    func suggestedExportName(for format: SystemLogExportFormat) -> String {
        let day = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "\(kindTitle) \(day).\(format.fileExtension)"
    }

    func unblock(_ addresses: [BlockedAddress]) async -> DSMOperationOutcome {
        guard !addresses.isEmpty else { return .cancelled }
        let values = addresses.map(\.address)
        busyAddresses.formUnion(values)
        defer { busyAddresses.subtract(values) }
        do {
            try await session.withClient { try await $0.unblockAddresses(values) }
            // The list is reloaded rather than patched in place: auto-block may have added or
            // expired addresses meanwhile.
            await loadBlockedAddresses(generation: loadGeneration)
            if values.count == 1, let only = values.first {
                return .success(String(localized: "logs.security.unblock.result.single", defaultValue: "Address unblocked: \(only)"))
            }
            return .success(String(localized: "logs.security.unblock.result.multiple", defaultValue: "\(values.count) addresses unblocked"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "logs.security.unblock.error", defaultValue: "Unblock failed: \(reason)"))
        }
    }

    // MARK: - Presentation

    /// Entries actually shown. Only severity is filtered here: the keyword has already been
    /// applied by the NAS.
    var visibleLogs: [SystemLogEntry] {
        guard levelFilter != .all else { return logs }
        return logs.filter { matches(levelFilter, $0.level) }
    }

    private func matches(_ filter: LevelFilter, _ level: SystemLogEntry.Level?) -> Bool {
        switch (filter, level) {
        case (.all, _): true
        case (.error, .error): true
        case (.warning, .warning): true
        case (.info, .info): true
        default: false
        }
    }

    /// A transfer log assigns no severity: the dash states the absence, where "unknown level"
    /// would suggest a value we had failed to read.
    func levelText(_ level: SystemLogEntry.Level?) -> String {
        switch level {
        case .info: String(localized: "common.level.information")
        case .warning: String(localized: "common.level.warning")
        case .error: String(localized: "common.level.error")
        case .other(let raw): raw.isEmpty ? String(localized: "common.level.unknown") : raw
        case nil: "—"
        }
    }

    func addressText(for entry: SystemLogEntry) -> String { entry.address ?? "—" }

    /// Operation recorded by a transfer log. DSM uses short, untranslated verbs; the most
    /// common ones are spelled out, the others left as they are.
    func operationText(for entry: SystemLogEntry) -> String {
        switch entry.operation?.lowercased() {
        case "read": String(localized: "common.metric.read")
        case "write": String(localized: "common.metric.write")
        case "delete": String(localized: "common.operation.deletion")
        case "rename": String(localized: "logs.transfer.action.rename")
        case "move": String(localized: "common.operation.moving")
        case "copy": String(localized: "common.operation.copy.noun")
        case "create": String(localized: "common.label.creation")
        case "mkdir": String(localized: "logs.transfer.action.folder_creation")
        case nil: "—"
        default: entry.operation ?? "—"
        }
    }

    /// File size. A folder has none, and the NAS writes zero there.
    func sizeText(for entry: SystemLogEntry) -> String {
        guard let fileSize = entry.fileSize else {
            return entry.isDirectory ? String(localized: "common.value.folder") : "—"
        }
        return fileSize.formatted(.byteCount(style: .file))
    }

    /// True when the current log describes transfers: its columns are not the same.
    var showsTransferColumns: Bool { kind.isTransfer }

    /// Log name. Transfer logs carry their protocol's name, spelled the way Synology writes
    /// it: those names are not translated.
    func kindText(_ kind: SystemLogKind) -> String {
        switch kind {
        case .system: String(localized: "logs.log_type.system")
        case .connection: String(localized: "logs.log_type.connection")
        case .afp: "AFP"
        case .cifs: "SMB"
        case .fileStation: "File Station"
        case .ftp: "FTP"
        case .tftp: "TFTP"
        case .webdav: "WebDAV"
        }
    }

    /// Screen title for the current log, and the wording announced after a change.
    var kindTitle: String {
        switch kind {
        case .system, .connection: kindText(kind)
        default: String(localized: "logs.log_type.transfers", defaultValue: "\(kindText(kind)) transfers")
        }
    }

    func filterText(_ filter: LevelFilter) -> String {
        switch filter {
        case .all: String(localized: "logs.filter.level.all")
        case .error: String(localized: "common.level.errors")
        case .warning: String(localized: "common.level.warnings")
        case .info: String(localized: "common.label.information")
        }
    }

    /// Entry category. The technical value is translated by the app, so that it follows the
    /// app's language and not the DSM account's; the NAS translation only serves as a fallback
    /// for a category we do not know.
    func categoryText(for entry: SystemLogEntry) -> String {
        switch entry.technicalCategory?.lowercased() {
        case "system": String(localized: "common.label.system")
        case "connection": String(localized: "logs.transfer.action.connection")
        case "filetransfer": String(localized: "logs.transfer.action.file_transfer")
        default: entry.translatedCategory ?? "—"
        }
    }

    func accountText(for entry: SystemLogEntry) -> String { entry.account ?? "—" }

    /// Timestamp rendered in the Mac's language. A dash when DSM sent a form we could not
    /// read: the entry stays listed, with no invented date.
    func dateText(for entry: SystemLogEntry) -> String {
        guard let recordedAt = entry.recordedAt else { return "—" }
        return recordedAt.formatted(date: .abbreviated, time: .standard)
    }

    func blockedAtText(for address: BlockedAddress) -> String {
        guard let blockedAt = address.blockedAt else { return "—" }
        return blockedAt.formatted(date: .abbreviated, time: .standard)
    }

    /// A block with no expiry is DSM's default. The NAS then sends zero, which it formats
    /// itself as 1970 — hence a date never taken as is.
    func expiryText(for address: BlockedAddress) -> String {
        guard let expiresAt = address.expiresAt else {
            return String(localized: "logs.security.autoblock.expiry.permanent")
        }
        return expiresAt.formatted(date: .abbreviated, time: .shortened)
    }

    func countryText(for address: BlockedAddress) -> String {
        guard let country = address.country, !country.isEmpty else {
            return String(localized: "logs.security.location.unknown")
        }
        return Locale.current.localizedString(forRegionCode: country) ?? country
    }

    // MARK: - Sign-in activity

    /// The alert as a single sentence. The NAS supplies none: it sends a key from its
    /// catalogue plus arguments, which its web client assembles. Each known key therefore has
    /// its own complete sentence, and both the account and the address stay in their columns
    /// instead of being repeated here.
    func description(of event: LoginActivityEvent) -> String {
        switch event.kind {
        case .abnormalLogin:
            if let city = event.details.city, let country = countryName(event.details.countryCode) {
                return String(localized: "logs.security.alert.unusual_signin.from_location", defaultValue: "Unusual sign-in from \(city), \(country)")
            }
            if let country = countryName(event.details.countryCode) {
                return String(localized: "logs.security.alert.unusual_signin.from", defaultValue: "Unusual sign-in from \(country)")
            }
            return String(localized: "logs.security.alert.unusual_signin")
        case .bruteForceAttack:
            if let attempts = event.details.attemptCount,
               let minutes = event.details.thresholdMinutes {
                return String(
                    localized: "logs.security.autoblock.summary",
                    defaultValue: "\(attempts) failed sign-in attempts within \(minutes) minutes"
                )
            }
            return String(localized: "logs.security.alert.repeated_signin")
        case .unknown(let section, let identifier):
            // The NAS reported something we do not know how to word: say so, rather than
            // inventing a sentence or hiding the alert.
            let key = identifier.isEmpty ? section : "\(section):\(identifier)"
            return String(localized: "logs.security.alert.unrecognized", defaultValue: "Unrecognised security alert (\(key))")
        }
    }

    func severityText(_ severity: LoginActivityEvent.Severity) -> String {
        switch severity {
        case .low: String(localized: "logs.security.severity.low")
        case .medium: String(localized: "logs.security.severity.medium")
        case .high: String(localized: "logs.security.severity.high")
        case .other(let raw): raw.isEmpty ? String(localized: "logs.security.severity.unknown") : raw
        }
    }

    func accountText(for event: LoginActivityEvent) -> String {
        event.account ?? event.details.user ?? "—"
    }

    /// The addresses of an alert. A brute-force attack can carry several.
    func addressText(for event: LoginActivityEvent) -> String {
        let addresses = event.details.allAddresses
        guard !addresses.isEmpty else { return "—" }
        return addresses.formatted(.list(type: .and))
    }

    func dateText(for event: LoginActivityEvent) -> String {
        guard let recordedAt = event.recordedAt else { return "—" }
        return recordedAt.formatted(date: .abbreviated, time: .standard)
    }

    /// The NAS sends a two-letter country code; the Mac knows how to name it in the user's
    /// language.
    private func countryName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    var loginActivitySummary: String {
        if let loginActivityError { return loginActivityError }
        let high = loginActivity.filter { $0.severity == .high }.count
        return String(
            localized: "logs.security.alerts.summary",
            defaultValue: "\(loginActivity.count) sign-in alerts, including \(high) of high severity"
        )
    }

    func canUnblock(_ address: BlockedAddress) -> Bool {
        !busyAddresses.contains(address.address)
    }

    /// True when the NAS keeps more of them than what has been loaded.
    var isTruncated: Bool { totalLogCount > logs.count }

    /// Count of the severities present in the loaded page. Recomputed here rather than read
    /// from the response: the NAS does return `errorCount` and its neighbours, but they cover
    /// the whole page, whereas the screen may filter part of it out.
    var visibleErrorCount: Int { visibleLogs.filter { $0.level == .error }.count }
    var visibleWarningCount: Int { visibleLogs.filter { $0.level == .warning }.count }

    var summary: String {
        if let errorMessage { return errorMessage }
        // A transfer log has no severity: announcing "0 errors" there would be misleading.
        if showsTransferColumns {
            if isTruncated {
                return String(
                    localized: "common.status.entries_shown",
                    defaultValue: "\(visibleLogs.count) entries shown out of \(totalLogCount)"
                )
            }
            return String(localized: "logs.entries.summary", defaultValue: "\(visibleLogs.count) log entries")
        }
        let errors = visibleErrorCount
        let warnings = visibleWarningCount
        if isTruncated {
            return String(
                localized: "logs.entries.filtered_summary",
                defaultValue: "\(visibleLogs.count) of \(totalLogCount) entries shown, including \(errors) errors and \(warnings) warnings"
            )
        }
        return String(
            localized: "logs.entries.summary_with_levels",
            defaultValue: "\(visibleLogs.count) log entries, including \(errors) errors and \(warnings) warnings"
        )
    }
}
