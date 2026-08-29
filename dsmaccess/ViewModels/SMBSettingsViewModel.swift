//
//  SMBSettingsViewModel.swift
//  dsmaccess
//
//  State of the SMB tab of the file services. Settings are edited then applied together,
//  the way DSM does it: the NAS restarts Samba on every write, so applying one field at a
//  time would cut the shares as many times.
//
//  The view model keeps what the NAS returned beside what the user is editing. The
//  difference between the two is what tells whether there is anything to apply, which
//  screen to announce, and which of the two `set` calls to send.
//

import Foundation
import Observation

@MainActor
@Observable
final class SMBSettingsViewModel {
    /// Settings as the NAS last returned them.
    private(set) var applied: SMBSettings?
    /// Settings as the user is editing them. The view binds to this one.
    var draft: SMBSettings?
    /// Whether SMB transfers are logged, as last read. Comes from another API than the rest.
    private(set) var appliedLogsTransfers = false
    var draftLogsTransfers = false

    private(set) var isLoading = false
    private(set) var isApplying = false
    /// Load failure. An apply failure travels back to the caller instead, as an alert.
    private(set) var loadError: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    var hasChanges: Bool {
        guard let applied, let draft else { return false }
        return draft != applied || draftLogsTransfers != appliedLogsTransfers
    }

    private var basicChanged: Bool {
        guard let applied, let draft else { return false }
        return draft.basic != applied.basic || draftLogsTransfers != appliedLogsTransfers
    }

    private var advancedChanged: Bool {
        guard let applied, let draft else { return false }
        return draft.advanced != applied.advanced
    }

    /// Reads the settings and the transfer log flag. The two are independent: the log flag
    /// lives in SYNO.Core.SyslogClient.FileTransfer, which the SMB `get` knows nothing about.
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let settings = try await session.withClient { try await $0.smbSettings() }
            let logging = try await session.withClient { try await $0.fileTransferLogging() }
            guard generation == loadGeneration else { return }
            applied = settings
            draft = settings
            appliedLogsTransfers = logging.enabled.contains(.cifs)
            draftLogsTransfers = appliedLogsTransfers
            loadError = nil
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            loadError = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Sends what changed, then reads the settings back. DSM itself relies on that read: the
    /// NAS adjusts some fields on its own, and the screen must show what it kept, not what
    /// was asked.
    func apply() async -> DSMOperationOutcome {
        guard let draft, hasChanges else {
            return .success(String(localized: "smb.apply.nothing_to_apply"))
        }
        isApplying = true
        defer { isApplying = false }

        let sendsBasic = basicChanged
        let sendsAdvanced = advancedChanged
        var basicApplied = false

        do {
            if sendsBasic {
                try await session.withClient {
                    try await $0.setSMBBasicSettings(draft.basic, logsTransfers: draftLogsTransfers)
                }
                basicApplied = true
            }
            if sendsAdvanced {
                try await session.withClient {
                    try await $0.setSMBAdvancedSettings(draft.advanced, isEnabled: draft.basic.isEnabled)
                }
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            await load()
            // Saying which half went through matters: the screen now shows a mix of what was
            // applied and what was refused, and the user has to know which is which.
            if basicApplied {
                return .failure(
                    String(
                        localized: "smb.apply.partial.error",
                        defaultValue: "The SMB settings were applied, but the advanced settings were refused: \(reason)"
                    )
                )
            }
            return .failure(
                String(
                    localized: "smb.apply.error",
                    defaultValue: "The SMB settings could not be applied: \(reason)"
                )
            )
        }

        await load()
        return .success(String(localized: "smb.apply.done"))
    }

    /// Drops the pending edits and shows the applied settings again.
    func revert() {
        draft = applied
        draftLogsTransfers = appliedLogsTransfers
    }

    /// Announced once the screen has finished loading.
    var summary: String {
        guard let applied else {
            return String(localized: "smb.summary.unavailable")
        }
        return applied.basic.isEnabled
            ? String(localized: "smb.summary.enabled")
            : String(localized: "smb.summary.disabled")
    }
}
