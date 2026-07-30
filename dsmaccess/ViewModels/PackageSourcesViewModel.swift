//
//  PackageSourcesViewModel.swift
//  dsmaccess
//
//  Loads and edits the Package Center third-party sources.
//

import Foundation
import Observation

@MainActor
@Observable
final class PackageSourcesViewModel {
    private(set) var sources: [PackageSource] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?
    var operationErrorMessage: String?

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
            let result = try await session.withClient { try await $0.packageSources() }
            guard generation == loadGeneration else { return }
            sources = result.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = Self.errorDescription(for: error)
        }
    }

    func save(
        name: String,
        feed: String,
        originalFeed: String?
    ) async -> DSMOperationOutcome {
        guard let source = Self.validatedSource(name: name, feed: feed) else {
            return .failure(
                String(localized: "common.validation.invalid_package_source")
            )
        }
        isSaving = true
        operationErrorMessage = nil
        defer { isSaving = false }
        do {
            if let originalFeed {
                try await session.withClient {
                    try await $0.updatePackageSource(source, originalFeed: originalFeed)
                }
            } else {
                try await session.withClient { try await $0.addPackageSource(source) }
            }
            await load()
            return .success(
                originalFeed == nil
                    ? String(localized: "packages.sources.add.success", defaultValue: "Source \(source.name) added")
                    : String(localized: "packages.sources.edit.success", defaultValue: "Source \(source.name) updated")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let message = String(
                localized: "packages.sources.save.error",
                defaultValue: "Failed to save the source: \(Self.errorDescription(for: error))"
            )
            operationErrorMessage = message
            return .failure(message)
        }
    }

    func delete(_ source: PackageSource) async -> DSMOperationOutcome {
        isSaving = true
        operationErrorMessage = nil
        defer { isSaving = false }
        do {
            try await session.withClient {
                try await $0.deletePackageSources(feeds: [source.feed])
            }
            await load()
            return .success(String(localized: "packages.sources.remove.success", defaultValue: "Source \(source.name) removed"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let message = String(
                localized: "packages.sources.remove.error",
                defaultValue: "Failed to remove \(source.name): \(Self.errorDescription(for: error))"
            )
            operationErrorMessage = message
            return .failure(message)
        }
    }

    static func validatedSource(name: String, feed: String) -> PackageSource? {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFeed = feed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              let url = URL(string: normalizedFeed),
              url.scheme?.lowercased() == "https",
              url.host != nil else { return nil }
        return PackageSource(name: normalizedName, feed: normalizedFeed)
    }

    private static func errorDescription(for error: Error) -> String {
        (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}
