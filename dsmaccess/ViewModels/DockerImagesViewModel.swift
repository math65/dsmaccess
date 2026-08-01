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
    /// Import, export and upload share one flag: they all move one image at a time, and letting
    /// two of them run at once would only produce two progress lines for one NAS.
    private(set) var isTransferring = false
    private(set) var transferDescription: String?
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

    /// What the image declares about itself. DSM keys this on the image identifier, and its
    /// answer carries no name, so the caller keeps the one it already has.
    func detail(for image: DockerImage) async throws -> DockerImageDetail {
        try await session.withClient { try await $0.dockerImageDetail(identity: image.id) }
    }

    // MARK: - Moving images in and out

    /// Writes the image to a folder of the NAS. DSM names the archive itself, so the result
    /// says where it landed rather than pretending the name was a choice.
    func export(_ image: DockerImage, tag: String, to folderPath: String) async -> DSMOperationOutcome {
        isTransferring = true
        transferDescription = String(
            localized: "containers.image.export.in_progress",
            defaultValue: "Exporting \(image.displayName)"
        )
        defer {
            isTransferring = false
            transferDescription = nil
        }

        do {
            try await session.withClient {
                try await $0.exportDockerImage(
                    repository: image.repository,
                    tag: tag,
                    folderPath: folderPath
                )
            }
            let fileName = image.exportArchiveName(tag: tag)
            return .success(String(
                localized: "containers.image.export.success",
                defaultValue: "Image exported to \(folderPath)/\(fileName)"
            ))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(
                localized: "containers.image.export.failed",
                defaultValue: "Exporting \(image.displayName) failed: \(reason)"
            ))
        }
    }

    /// Loads an archive that already sits on the NAS.
    func importImage(at path: String) async -> DSMOperationOutcome {
        isTransferring = true
        transferDescription = String(localized: "containers.image.import.in_progress")
        defer {
            isTransferring = false
            transferDescription = nil
        }

        do {
            try await session.withClient { try await $0.importDockerImage(path: path) }
            await load(silently: true)
            return .success(String(localized: "containers.image.import.success"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(
                localized: "containers.image.import.failed",
                defaultValue: "Importing failed: \(reason)"
            ))
        }
    }

    /// Sends an archive from the Mac. The progress is reported in bytes because DSM gives no
    /// step of its own for an upload.
    func uploadImage(at fileURL: URL) async -> DSMOperationOutcome {
        isTransferring = true
        transferDescription = String(localized: "containers.image.upload.in_progress")
        defer {
            isTransferring = false
            transferDescription = nil
        }

        do {
            try await session.withClient { client in
                try await client.uploadDockerImage(at: fileURL) { [weak self] progress in
                    self?.transferDescription = Self.uploadProgress(progress)
                }
            }
            await load(silently: true)
            return .success(String(localized: "containers.image.import.success"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(
                localized: "containers.image.upload.failed",
                defaultValue: "Sending the archive failed: \(reason)"
            ))
        }
    }

    private static func uploadProgress(_ progress: DSMTransferProgress) -> String {
        guard let fraction = progress.fractionCompleted else {
            return String(localized: "containers.image.upload.in_progress")
        }
        return String(
            localized: "containers.image.upload.progress",
            defaultValue: "Sending the archive: \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        )
    }

    func shareNames() async throws -> [String] {
        try await session.withClient { try await $0.listShares() }.map(\.name)
    }

    func folders(in path: String) async throws -> [FileStationItem] {
        try await session.withClient { client in
            try await client.list(folderPath: path)
                .filter(\.isdir)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// The image archives of a folder. DSM writes them with a `.syno.tar` suffix, and offering
    /// anything else to import would only earn a refusal from the NAS.
    func archives(in path: String) async throws -> [FileStationItem] {
        try await session.withClient { client in
            try await client.list(folderPath: path)
                .filter { !$0.isdir && $0.name.hasSuffix(".syno.tar") }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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

    /// Downloads the newer build of an image already present, polling like a pull. The
    /// containers using it keep running on the old build until they are recreated.
    func upgrade(_ image: DockerImage) async -> DSMOperationOutcome {
        busyImageIDs.insert(image.id)
        isPulling = true
        pullDescription = String(
            localized: "containers.image.upgrade.in_progress",
            defaultValue: "Updating \(image.displayName)…"
        )
        defer {
            busyImageIDs.remove(image.id)
            isPulling = false
            pullDescription = nil
        }

        do {
            let task = try await session.withClient {
                try await $0.startDockerImageUpgrade(repository: image.repository)
            }
            while true {
                try Task.checkCancellation()
                let status = try await session.withClient {
                    try await $0.dockerImageUpgradeStatus(taskID: task.taskID)
                }
                if status.isFinished { break }
                try await Task.sleep(for: .seconds(2))
            }
            await load(silently: true)
            return .success(String(
                localized: "containers.image.upgrade.success",
                defaultValue: "Image updated: \(image.displayName)"
            ))
        } catch is CancellationError {
            return .cancelled
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(image.displayName): \(reason)"))
        }
    }

    /// Removes every image no container references, as Container Manager's button does.
    func prune() async -> DSMOperationOutcome {
        do {
            try await session.withClient { try await $0.pruneDockerImages() }
            await load(silently: true)
            return .success(String(localized: "containers.image.prune.success"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.operation_failed", defaultValue: "The operation failed: \(reason)"))
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
