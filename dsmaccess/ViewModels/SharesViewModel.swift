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
    func create(name: String, volumePath: String, description: String) async -> DSMOperationOutcome {
        do {
            try await session.withClient {
                try await $0.createSharedFolder(
                    name: name,
                    volumePath: volumePath,
                    description: description
                )
            }
            await load()
            return .success(String(localized: "shares.create.success", defaultValue: "Shared folder created: \(name)"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(String(localized: "shares.create.error", defaultValue: "Failed to create the folder: \(reason(for: error))"))
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
            case 3309: return String(localized: "shares.create.error.limit_reached")
            default: break
            }
        }
        return (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}
