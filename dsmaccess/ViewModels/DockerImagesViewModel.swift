//
//  DockerImagesViewModel.swift
//  dsmaccess
//
//  Local images: inventory, download from the registry, deletion.
//

import Foundation
import Observation

@MainActor
@Observable
final class DockerImagesViewModel {
    private(set) var images: [DockerImage] = []
    private(set) var registryName: String?
    private(set) var isLoading = false
    private(set) var busyImageIDs: Set<String> = []
    private(set) var isPulling = false
    private(set) var pullDescription: String?
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
            let result = try await session.withClient { try await $0.listDockerImages() }.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            guard generation == loadGeneration else { return }
            images = result
            // The active registry names where a new image would be pulled from. Read
            // best-effort: a failure must not take the whole tab down with it.
            registryName = try? await session.withClient { try await $0.dockerRegistries() }.selected
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ image: DockerImage) async -> DSMOperationOutcome {
        busyImageIDs.insert(image.id)
        defer { busyImageIDs.remove(image.id) }

        do {
            try await session.withClient {
                try await $0.deleteDockerImage(repository: image.repository, tags: image.tags)
            }
            await load(silently: true)
            return .success(String(
                localized: "containers.image.delete.success",
                defaultValue: "Image deleted: \(image.displayName)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(image.displayName): \(reason)"))
        }
    }

    /// Starts a download then polls it to completion. The task identifier lives on the NAS:
    /// cancelling here abandons the tracking, not the download.
    func pull(repository: String, tag: String) async -> DSMOperationOutcome {
        let name = tag.isEmpty ? repository : "\(repository):\(tag)"
        isPulling = true
        pullDescription = String(
            localized: "containers.image.pull.in_progress",
            defaultValue: "Downloading \(name)…"
        )
        defer {
            isPulling = false
            pullDescription = nil
        }

        do {
            let task = try await session.withClient {
                try await $0.startDockerImagePull(repository: repository, tag: tag.isEmpty ? "latest" : tag)
            }
            while true {
                try Task.checkCancellation()
                let status = try await session.withClient {
                    try await $0.dockerImagePullStatus(taskID: task.taskID)
                }
                if status.isFinished { break }
                if let downloaded = status.downloadedBytes, downloaded > 0 {
                    pullDescription = String(
                        localized: "containers.image.pull.progress",
                        defaultValue: "Downloading \(name): \(downloaded.formatted(.byteCount(style: .file)))"
                    )
                }
                try await Task.sleep(for: .seconds(2))
            }
            await load(silently: true)
            return .success(String(
                localized: "containers.image.pull.success",
                defaultValue: "Image downloaded: \(name)"
            ))
        } catch is CancellationError {
            return .cancelled
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(name): \(reason)"))
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let total = images.compactMap(\.sizeBytes).reduce(0, +)
        return String(
            localized: "containers.image.summary.count",
            defaultValue: "\(images.count) images, \(total.formatted(.byteCount(style: .file)))"
        )
    }
}
