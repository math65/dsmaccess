//
//  DockerNetworksViewModel.swift
//  dsmaccess
//
//  Container networks, read-only.
//

import Foundation
import Observation

@MainActor
@Observable
final class DockerNetworksViewModel {
    private(set) var networks: [DockerNetwork] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(silently: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = !silently
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }

        do {
            let result = try await session.withClient { try await $0.listDockerNetworks() }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            guard generation == loadGeneration else { return }
            networks = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(
            localized: "containers.network.summary.count",
            defaultValue: "\(networks.count) networks"
        )
    }
}
