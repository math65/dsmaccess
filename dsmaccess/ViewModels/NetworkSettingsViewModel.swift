//
//  NetworkSettingsViewModel.swift
//  dsmaccess
//
//  Loads the NAS identity and network configuration.
//

import Foundation
import Observation

@MainActor
@Observable
final class NetworkSettingsViewModel {
    private(set) var info: NetworkInfo?
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
        defer {
            if generation == loadGeneration {
                isLoading = false
            }
        }
        do {
            let result = try await session.withClient { try await $0.networkInfo() }
            guard generation == loadGeneration else { return }
            info = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        guard let info else { return String(localized: "common.error.network_configuration_unavailable") }
        if let name = info.serverName, !name.isEmpty {
            return String(localized: "network.identity.server_name.value", defaultValue: "Server \(name)")
        }
        return String(localized: "network.loaded.announcement")
    }
}
