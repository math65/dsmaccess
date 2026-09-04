//
//  DockerNetworksViewModel.swift
//  dsmaccess
//
//  Container networks: listing, creation, removal, and which containers they carry.
//

import Foundation
import Observation

@MainActor
@Observable
final class DockerNetworksViewModel {
    private(set) var networks: [DockerNetwork] = []
    private(set) var isLoading = false
    private(set) var busyNetworkNames: Set<String> = []
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

    // MARK: - Creation

    func create(
        name: String,
        addressing: DockerNetworkAddressing,
        disablesMasquerade: Bool,
        enablesIPv6: Bool
    ) async -> DSMOperationOutcome {
        do {
            try await session.withClient {
                try await $0.createDockerNetwork(
                    name: name,
                    addressing: addressing,
                    disablesMasquerade: disablesMasquerade,
                    enablesIPv6: enablesIPv6
                )
            }
            await load(silently: true)
            return .success(String(
                localized: "containers.network.create.success",
                defaultValue: "Network created: \(name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            return .failure(creationFailure(error, name: name))
        }
    }

    /// The three refusals measured on the NAS. Anything else keeps DSM's own wording.
    private func creationFailure(_ error: Error, name: String) -> String {
        if case .apiError(let code, _) = error as? DSMError {
            switch code {
            case 1800:
                return String(
                    localized: "containers.network.create.error.name_taken",
                    defaultValue: "A network named \(name) already exists."
                )
            case 1805:
                return String(localized: "containers.network.create.error.gateway_taken")
            case 1807:
                return String(localized: "containers.network.create.error.gateway_out_of_range")
            default:
                break
            }
        }
        let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        return String(
            localized: "containers.network.create.failed",
            defaultValue: "Creating \(name) failed: \(reason)"
        )
    }

    // MARK: - Removal

    /// Removes a network, and tells the truth about it.
    ///
    /// DSM answers `success: true` even when it removed nothing, so the refusals in
    /// `data.failed` are what decides the outcome here — not the envelope.
    func remove(_ network: DockerNetwork) async -> DSMOperationOutcome {
        busyNetworkNames.insert(network.name)
        defer { busyNetworkNames.remove(network.name) }

        do {
            let result = try await session.withClient {
                try await $0.removeDockerNetworks(named: [network.name])
            }
            await load(silently: true)
            guard let failure = result.failed.first else {
                return .success(String(
                    localized: "containers.network.remove.success",
                    defaultValue: "Network removed: \(network.name)"
                ))
            }
            guard let message = failure.message else {
                return .failure(String(
                    localized: "containers.network.remove.failed",
                    defaultValue: "Removing \(network.name) failed."
                ))
            }
            return .failure(String(
                localized: "containers.network.remove.failed_with_reason",
                defaultValue: "Removing \(network.name) failed: \(message)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(network.name): \(reason)"))
        }
    }

    // MARK: - Attached containers

    func attachableContainers() async throws -> [DockerNetworkContainer] {
        try await session.withClient { try await $0.dockerNetworkContainers() }
    }

    /// Applies the wanted set of containers for a network. DSM works out the attachments and
    /// detachments itself from this list.
    func setContainers(of network: DockerNetwork, to containerNames: [String]) async -> DSMOperationOutcome {
        busyNetworkNames.insert(network.name)
        defer { busyNetworkNames.remove(network.name) }

        do {
            try await session.withClient {
                try await $0.setDockerNetworkContainers(
                    networkName: network.name,
                    containerNames: containerNames
                )
            }
            await load(silently: true)
            return .success(String(
                localized: "containers.network.containers.success",
                defaultValue: "Connections updated for \(network.name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(network.name): \(reason)"))
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
