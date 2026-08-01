//
//  DockerRegistriesViewModel.swift
//  dsmaccess
//
//  Image registries: the list of repositories, which one is active, and searching it for
//  images to download.
//

import Foundation
import Observation

@MainActor
@Observable
final class DockerRegistriesViewModel {
    private(set) var registries: [DockerRegistry] = []
    /// Name of the registry images are pulled from. Only one is active at a time.
    private(set) var activeRegistryName: String?
    private(set) var isLoading = false
    private(set) var busyRegistryNames: Set<String> = []
    var errorMessage: String?

    private(set) var results: [DockerRegistrySearchResult] = []
    private(set) var isSearching = false
    private(set) var searchSummary: String?
    private(set) var searchFailed = false

    /// How many results one search brings back. DSM answers in the hundreds of thousands for a
    /// common word, and a list that long is worse than useless to walk through.
    private static let searchLimit = 50

    private let session: SessionStore
    private var loadGeneration = 0
    private var searchGeneration = 0

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
            let result = try await session.withClient { try await $0.dockerRegistries() }
            guard generation == loadGeneration else { return }
            registries = result.registries.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            activeRegistryName = result.selected
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    var activeRegistry: DockerRegistry? {
        guard let activeRegistryName else { return nil }
        return registries.first { $0.name == activeRegistryName }
    }

    // MARK: - Repository list

    func create(
        name: String,
        url: String,
        username: String,
        password: String,
        trustsSelfSignedCertificate: Bool
    ) async -> DSMOperationOutcome {
        do {
            try await session.withClient {
                try await $0.createDockerRegistry(
                    name: name,
                    url: url,
                    username: username,
                    password: password,
                    trustsSelfSignedCertificate: trustsSelfSignedCertificate
                )
            }
            await load(silently: true)
            return .success(String(
                localized: "containers.registry.create.success",
                defaultValue: "Registry added: \(name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(
                localized: "containers.registry.create.failed",
                defaultValue: "Adding \(name) failed: \(reason)"
            ))
        }
    }

    /// Edits a registry. `oldName` is what designates it on the NAS, so renaming works by
    /// sending a different `name` alongside it.
    func update(
        _ registry: DockerRegistry,
        name: String,
        url: String,
        username: String,
        password: String,
        trustsSelfSignedCertificate: Bool
    ) async -> DSMOperationOutcome {
        busyRegistryNames.insert(registry.name)
        defer { busyRegistryNames.remove(registry.name) }

        do {
            try await session.withClient {
                try await $0.updateDockerRegistry(
                    oldName: registry.name,
                    name: name,
                    url: url,
                    username: username,
                    password: password,
                    trustsSelfSignedCertificate: trustsSelfSignedCertificate
                )
            }
            await load(silently: true)
            return .success(String(
                localized: "containers.registry.edit.success",
                defaultValue: "Registry saved: \(name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(
                localized: "containers.registry.edit.failed",
                defaultValue: "Saving \(name) failed: \(reason)"
            ))
        }
    }

    func delete(_ registry: DockerRegistry) async -> DSMOperationOutcome {
        busyRegistryNames.insert(registry.name)
        defer { busyRegistryNames.remove(registry.name) }

        do {
            try await session.withClient { try await $0.deleteDockerRegistry(named: registry.name) }
            await load(silently: true)
            return .success(String(
                localized: "containers.registry.delete.success",
                defaultValue: "Registry removed: \(registry.name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(registry.name): \(reason)"))
        }
    }

    /// Makes a registry the active one, and clears results that came from the previous one:
    /// search only ever queries the active registry.
    func use(_ registry: DockerRegistry) async -> DSMOperationOutcome {
        busyRegistryNames.insert(registry.name)
        defer { busyRegistryNames.remove(registry.name) }

        do {
            try await session.withClient { try await $0.useDockerRegistry(named: registry.name) }
            await load(silently: true)
            clearSearch()
            return .success(String(
                localized: "containers.registry.use.success",
                defaultValue: "Images are now downloaded from \(registry.name)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(registry.name): \(reason)"))
        }
    }

    // MARK: - Image search

    func clearSearch() {
        searchGeneration += 1
        results = []
        searchSummary = nil
        searchFailed = false
        isSearching = false
    }

    /// Searches the active registry. Older answers are dropped so a slow search cannot land on
    /// top of a newer one.
    func search(keyword: String) async {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            clearSearch()
            return
        }

        searchGeneration += 1
        let generation = searchGeneration
        isSearching = true
        searchFailed = false
        defer { if generation == searchGeneration { isSearching = false } }

        do {
            let page = try await session.withClient {
                try await $0.searchDockerImages(keyword: keyword, offset: 0, limit: Self.searchLimit)
            }
            guard generation == searchGeneration else { return }
            results = page.results
            searchSummary = summary(for: page)
        } catch {
            guard generation == searchGeneration, !DSMError.isCancellation(error) else { return }
            results = []
            searchFailed = true
            searchSummary = searchFailureMessage(error)
        }
    }

    private func summary(for page: DockerRegistrySearchPage) -> String {
        let registryName = activeRegistryName ?? ""
        guard !page.results.isEmpty else {
            return String(
                localized: "containers.registry.search.none",
                defaultValue: "No image found in \(registryName)"
            )
        }
        guard let total = page.total, total > page.results.count else {
            return String(
                localized: "containers.registry.search.count",
                defaultValue: "\(page.results.count) images found in \(registryName)"
            )
        }
        return String(
            localized: "containers.registry.search.count_partial",
            defaultValue: "First \(page.results.count) of \(total) images found in \(registryName)"
        )
    }

    /// A registry with no search API is not a failure of the NAS: ghcr.io and most private
    /// registries simply do not answer this call, and saying so is more useful than the raw
    /// DSM error.
    private func searchFailureMessage(_ error: Error) -> String {
        let registryName = activeRegistryName ?? ""
        if case .apiError(let code) = error as? DSMError, code == 1052 || code == 1053 {
            return String(
                localized: "containers.registry.search.unsupported",
                defaultValue: "\(registryName) does not offer an image search. Enter the image name in the Images tab to download from it."
            )
        }
        let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        return String(
            localized: "containers.registry.search.failed",
            defaultValue: "Search failed: \(reason)"
        )
    }

    func tags(for repository: String) async throws -> [DockerImageTag] {
        try await session.withClient { try await $0.dockerImageTags(repository: repository) }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        guard let activeRegistryName else {
            return String(
                localized: "containers.registry.summary.count",
                defaultValue: "\(registries.count) registries"
            )
        }
        return String(
            localized: "containers.registry.summary.count_active",
            defaultValue: "\(registries.count) registries, downloading from \(activeRegistryName)"
        )
    }
}
