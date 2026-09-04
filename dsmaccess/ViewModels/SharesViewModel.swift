//
//  SharesViewModel.swift
//  dsmaccess
//
//  Loads the list of shared folders (SYNO.Core.Share) and drives their creation/deletion.
//  The actions return an already-localized message to announce to VoiceOver.
//

import Foundation
import Observation

@MainActor
@Observable
final class SharesViewModel {
    private(set) var shares: [SharedFolder] = []
    /// Paths of the volumes available for creation ("/volume1"…).
    private(set) var volumes: [String] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// Conversion currently rewriting a folder, so the screen can say what the NAS is doing
    /// instead of leaving the folder unavailable without explanation.
    private(set) var conversion: ShareConversion?

    private let session: SessionStore
    private var loadGeneration = 0
    private var conversionTask: Task<Void, Never>?

    init(session: SessionStore) {
        self.session = session
    }

    struct ShareConversion: Equatable, Sendable {
        let folderName: String
        let taskID: String
        var percent: Int
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { client in
                let shares = try await client.listSharedFolders().sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                let info: StorageInfo?
                do {
                    info = try await client.storageInfo()
                } catch DSMError.sessionExpired {
                    throw DSMError.sessionExpired
                } catch {
                    info = nil
                }
                return (shares, info)
            }
            guard generation == loadGeneration else { return }
            shares = result.0
            volumes = (result.1?.volumes ?? [])
                .compactMap { $0.numId.map { "/volume\($0)" } }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Creates a shared folder. Returns the message to announce.
    func create(_ creation: SharedFolderCreation) async -> DSMOperationOutcome {
        let name = creation.name
        do {
            try await session.withClient { try await $0.createSharedFolder(creation) }
            await load()
            return .success(String(localized: "shares.create.success", defaultValue: "Shared folder created: \(name)"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "shares.create.error", defaultValue: "Failed to create the folder: \(reason(for: error))"))
        }
    }

    /// Applies edited settings. Returns the message to announce.
    ///
    /// Switching encryption on or off is a background conversion on the NAS: the call returns
    /// as soon as DSM accepts it, and the folder reaches its new state later, which is why that
    /// case gets its own message instead of a plain "saved".
    func update(_ changes: SharedFolderChanges) async -> DSMOperationOutcome {
        let name = changes.name
        do {
            let taskID = try await session.withClient { try await $0.updateSharedFolder(changes) }
            await load()
            if let taskID {
                startTrackingConversion(taskID: taskID, folderName: name)
            }
            switch changes.encryption {
            case .encrypt:
                return .success(String(localized: "shares.edit.success.encrypting", defaultValue: "Settings saved. The NAS is encrypting \(name); its contents stay unavailable until that finishes."))
            case .decrypt:
                return .success(String(localized: "shares.edit.success.decrypting", defaultValue: "Settings saved. The NAS is removing the encryption of \(name); its contents stay unavailable until that finishes."))
            case nil:
                return .success(String(localized: "shares.edit.success", defaultValue: "Settings saved for \(name)"))
            }
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "shares.edit.error", defaultValue: "Failed to save the settings: \(reason(for: error))"))
        }
    }

    /// Empties the recycle bin of a folder. Returns the message to announce.
    func emptyRecycleBin(_ folder: SharedFolder) async -> DSMOperationOutcome {
        let name = folder.name
        do {
            try await session.withClient { try await $0.emptySharedFolderRecycleBin(name: name) }
            return .success(String(localized: "shares.recycle_bin.empty.success", defaultValue: "The recycle bin of \(name) is empty."))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "shares.recycle_bin.empty.error", defaultValue: "Failed to empty the recycle bin: \(reason(for: error))"))
        }
    }

    /// Stops a conversion in progress. DSM leaves the folder in the state it had reached.
    func cancelConversion() async -> DSMOperationOutcome? {
        guard let conversion else { return nil }
        do {
            try await session.withClient {
                try await $0.cancelSharedFolderConversion(taskID: conversion.taskID)
            }
            stopTrackingConversion()
            await load()
            return .success(String(localized: "shares.conversion.cancelled", defaultValue: "The conversion of \(conversion.folderName) was stopped."))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "shares.conversion.cancel.error", defaultValue: "Failed to stop the conversion: \(reason(for: error))"))
        }
    }

    /// Follows the background conversion until DSM reports it finished, announcing its progress
    /// as it goes: the folder is unavailable for the whole time, and nothing else would say so.
    private func startTrackingConversion(taskID: String, folderName: String) {
        conversionTask?.cancel()
        conversion = ShareConversion(folderName: folderName, taskID: taskID, percent: 0)
        conversionTask = Task { [weak self] in
            var lastAnnounced = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                let status: ShareConversionStatus
                do {
                    status = try await session.withClient {
                        try await $0.sharedFolderConversionStatus(taskID: taskID)
                    }
                } catch {
                    guard !DSMError.isCancellation(error) else { return }
                    conversion = nil
                    VoiceOver.announce(
                        String(localized: "shares.conversion.tracking.error", defaultValue: "The progress of \(folderName) can no longer be followed. Refresh the list to see its state."),
                        category: .error,
                        priority: .high
                    )
                    return
                }
                guard !Task.isCancelled else { return }
                conversion?.percent = status.percent
                if status.finished {
                    conversion = nil
                    await load()
                    VoiceOver.announce(
                        String(localized: "shares.conversion.finished", defaultValue: "\(folderName) is ready; the NAS has finished rewriting it."),
                        priority: .high
                    )
                    return
                }
                // Announced by quarters: spoken at every poll, this would talk over everything
                // else for as long as the conversion lasts.
                if status.percent >= lastAnnounced + 25 {
                    lastAnnounced = status.percent - status.percent % 25
                    VoiceOver.announce(
                        String(localized: "shares.conversion.progress", defaultValue: "\(folderName): \(status.percent)%"),
                        category: .progress,
                        priority: .low
                    )
                }
            }
        }
    }

    private func stopTrackingConversion() {
        conversionTask?.cancel()
        conversionTask = nil
        conversion = nil
    }

    /// Locks an encrypted folder. Returns the message to announce.
    func lock(_ folder: SharedFolder) async -> DSMOperationOutcome {
        let name = folder.name
        do {
            try await session.withClient { try await $0.lockSharedFolder(name: name) }
            await load()
            return .success(String(localized: "shares.lock.success", defaultValue: "\(name) is locked; its contents are unavailable until it is unlocked."))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "shares.lock.error", defaultValue: "Failed to lock the folder: \(reason(for: error))"))
        }
    }

    /// Unlocks an encrypted folder with its key. Returns the message to announce.
    func unlock(_ folder: SharedFolder, key: String) async -> DSMOperationOutcome {
        let name = folder.name
        do {
            try await session.withClient { try await $0.unlockSharedFolder(name: name, key: key) }
            await load()
            return .success(String(localized: "shares.unlock.success", defaultValue: "\(name) is unlocked."))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "shares.unlock.error", defaultValue: "Failed to unlock the folder: \(reason(for: error))"))
        }
    }

    /// Deletes a shared folder. Returns the message to announce.
    func delete(_ folder: SharedFolder) async -> DSMOperationOutcome {
        let name = folder.name
        do {
            try await session.withClient { try await $0.deleteSharedFolder(name: name) }
            await load()
            return .success(String(localized: "shares.delete.success", defaultValue: "Shared folder deleted: \(name)"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "common.error.delete_failed", defaultValue: "Delete failed: \(reason(for: error))"))
        }
    }

    /// Summary announced to VoiceOver once loaded.
    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "common.count.shared_folders", defaultValue: "\(shares.count) shared folders")
    }

    /// Error message, with friendly cases for the known SYNO.Core.Share codes.
    private func reason(for error: Error) -> String {
        if case let DSMError.apiError(code, _) = error {
            switch code {
            case 3301: return String(localized: "shares.create.error.name_taken")
            case 3308: return String(localized: "shares.encryption.error.wrong_key")
            case 3309: return String(localized: "shares.create.error.limit_reached")
            default: break
            }
        }
        return (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}
