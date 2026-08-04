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

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
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
            try await session.withClient { try await $0.updateSharedFolder(changes) }
            await load()
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
        if case let DSMError.apiError(code) = error {
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
