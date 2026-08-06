//
//  HyperBackupRestoreViewModel.swift
//  dsmaccess
//
//  Browsing one backup version and copying what it holds back out of it.
//

import Foundation
import Observation

@MainActor
@Observable
final class HyperBackupRestoreViewModel {
    let task: HyperBackupTask
    let version: HyperBackupVersion

    private(set) var entries: [HyperBackupEntry] = []
    private(set) var destinations: [HyperBackupRestoreDestination] = []
    private(set) var isLoading = false
    private(set) var isRestoring = false
    private(set) var isDownloading = false
    /// Bytes received so far, so a large file does not look stalled. Nil outside a download.
    private(set) var downloadProgress: DSMTransferProgress?
    /// Empty while at the backup root. Relative to it, with no leading slash, which is what
    /// the browsing API expects.
    private(set) var node = ""
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    /// Title of the completion sound or notification for both restore flavors.
    private static var restoreOperationTitle: String {
        String(localized: "hyper_backup.operation.restore", defaultValue: "Restore")
    }

    init(task: HyperBackupTask, version: HyperBackupVersion, session: SessionStore) {
        self.task = task
        self.version = version
        self.session = session
    }

    enum SortMode: String, CaseIterable, Identifiable {
        case name
        case modificationDate
        case size

        var id: Self { self }

        var title: String {
            switch self {
            case .name: String(localized: "common.column.name")
            case .modificationDate: String(localized: "common.column.date_modified")
            case .size: String(localized: "common.column.size")
            }
        }
    }

    var sortMode = SortMode.name
    var sortAscending = true

    /// Folders stay ahead of files whatever the axis, matching the File Station browser.
    var sortedEntries: [HyperBackupEntry] {
        entries.sorted { left, right in
            if left.isFolder != right.isFolder {
                return left.isFolder && !right.isFolder
            }
            let result: ComparisonResult
            switch sortMode {
            case .name:
                result = left.name.localizedStandardCompare(right.name)
            case .modificationDate:
                result = compare(left.modificationTimestamp, right.modificationTimestamp)
            case .size:
                result = compare(left.size, right.size)
            }
            return sortAscending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private func compare(_ left: Int?, _ right: Int?) -> ComparisonResult {
        let leftValue = left ?? -1
        let rightValue = right ?? -1
        if leftValue == rightValue { return .orderedSame }
        return leftValue < rightValue ? .orderedAscending : .orderedDescending
    }

    var isAtRoot: Bool { node.isEmpty }

    /// The folders walked through, so the view can offer a way back to each of them.
    var pathComponents: [String] {
        node.isEmpty ? [] : node.split(separator: "/").map(String.init)
    }

    /// Where a restore in place puts things back. At the root the entries are the backed-up
    /// shared folders themselves, so there is no enclosing path to name.
    var originDescription: String {
        isAtRoot ? String(localized: "hyper_backup.restore.origin.shares") : "/\(node)"
    }

    var locationDescription: String {
        isAtRoot
            ? String(localized: "hyper_backup.restore.location.root")
            : node.replacingOccurrences(of: "/", with: " › ")
    }

    func load(silently: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if !silently { isLoading = true }
        errorMessage = nil
        defer {
            if generation == loadGeneration { isLoading = false }
        }

        do {
            let requestedNode = node
            let loaded = try await session.withClient { client -> [HyperBackupEntry] in
                requestedNode.isEmpty
                    ? try await client.hyperBackupRoot(
                        taskID: task.taskID,
                        versionID: version.versionID
                    )
                    : try await client.hyperBackupEntries(
                        taskID: task.taskID,
                        versionID: version.versionID,
                        node: requestedNode
                    )
            }
            guard generation == loadGeneration else { return }
            entries = loaded.sorted {
                if $0.isFolder != $1.isFolder { return $0.isFolder }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            entries = []
            errorMessage = reason(for: error)
        }
    }

    /// The shared folders a destination can be picked under, named as the folder picker
    /// expects them: without their leading slash.
    var shareNames: [String] { destinations.map(\.name) }

    /// Turns the share path the picker returns into the physical one `copy` insists on:
    /// `/Documents/2026` becomes `/volume1/Documents/2026`. The mapping goes through the
    /// share's own `realPath` rather than assuming a volume, since a share names no volume.
    func physicalPath(for sharePath: String) -> String? {
        guard let destination = destinations.first(where: {
            sharePath == "/\($0.name)" || sharePath.hasPrefix("/\($0.name)/")
        }) else { return nil }
        let suffix = sharePath.dropFirst(destination.name.count + 1)
        return destination.physicalPath + suffix
    }

    func folders(in path: String) async throws -> [FileStationItem] {
        try await session.withClient { client in
            try await client.list(folderPath: path)
                .filter(\.isdir)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func createFolder(in parent: String, named name: String) async throws {
        try await session.withClient { try await $0.createFolder(in: parent, name: name) }
    }

    /// Loaded on demand rather than with the listing: the destinations only matter once the
    /// user asks to restore something.
    func loadDestinations() async {
        guard destinations.isEmpty else { return }
        do {
            let shares = try await session.withClient { try await $0.listShares() }
            destinations = shares.compactMap { share in
                // A share with no real path cannot be used: `copy` insists on the physical
                // location and refuses the share path.
                guard let physicalPath = share.additional?.realPath, !physicalPath.isEmpty else {
                    return nil
                }
                return HyperBackupRestoreDestination(name: share.name, physicalPath: physicalPath)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = reason(for: error)
        }
    }

    func open(_ entry: HyperBackupEntry) async {
        guard entry.isFolder else { return }
        node = entry.path
        await load()
    }

    func goUp() async {
        guard !isAtRoot else { return }
        var components = pathComponents
        components.removeLast()
        node = components.joined(separator: "/")
        await load()
    }

    func goToRoot() async {
        guard !isAtRoot else { return }
        node = ""
        await load()
    }

    /// Copies the chosen entries beside their originals rather than over them. The entries
    /// land directly in the destination, without their enclosing folders being recreated.
    func restore(
        _ selection: [HyperBackupEntry],
        to sharePath: String,
        overwriting: Bool
    ) async -> DSMOperationOutcome {
        guard !selection.isEmpty, !isRestoring else { return .cancelled }
        guard let destinationPath = physicalPath(for: sharePath) else {
            return .failure(String(localized: "hyper_backup.restore.error.unknown_destination", defaultValue: "\(sharePath) is not inside a shared folder this session can restore to"))
        }
        isRestoring = true
        defer { isRestoring = false }
        await OperationNotifier.prepare()

        let outcome: DSMOperationOutcome
        do {
            try await session.withClient {
                try await $0.copyFromHyperBackup(
                    taskID: task.taskID,
                    versionID: version.versionID,
                    node: node,
                    sourcePaths: selection.map(\.path),
                    destinationPath: destinationPath,
                    overwrite: overwriting
                )
            }
            outcome = .success(successMessage(for: selection, destination: sharePath))
        } catch {
            outcome = DSMError.isCancellation(error)
                ? .cancelled
                : .failure(failureMessage(for: error, destination: sharePath))
        }
        await OperationNotifier.signalCompletion(of: outcome, title: Self.restoreOperationTitle)
        return outcome
    }

    /// Writes the backed-up entries back over their originals. DSM gives no choice of
    /// destination or of overwriting here, so neither does this: the confirmation the view
    /// shows first is what makes the operation deliberate.
    func restoreInPlace(_ selection: [HyperBackupEntry]) async -> DSMOperationOutcome {
        guard let first = selection.first, !isRestoring else { return .cancelled }
        isRestoring = true
        defer { isRestoring = false }
        await OperationNotifier.prepare()

        let outcome: DSMOperationOutcome
        do {
            try await session.withClient {
                try await $0.restoreInPlaceFromHyperBackup(
                    taskID: task.taskID,
                    versionID: version.versionID,
                    node: node,
                    sourcePaths: selection.map(\.path),
                    originPath: first.path
                )
            }
            if selection.count == 1 {
                outcome = .success(String(localized: "hyper_backup.restore.in_place.announcement.one", defaultValue: "\(first.name) put back where it came from"))
            } else {
                outcome = .success(String(localized: "hyper_backup.restore.in_place.announcement.several", defaultValue: "\(selection.count) items put back where they came from"))
            }
        } catch {
            outcome = DSMError.isCancellation(error)
                ? .cancelled
                : .failure(String(localized: "hyper_backup.restore.in_place.error", defaultValue: "Restoring to the original location failed: \(reason(for: error))"))
        }
        await OperationNotifier.signalCompletion(of: outcome, title: Self.restoreOperationTitle)
        return outcome
    }

    /// Pulls one file onto the Mac. DSM allows this for a single file at a time, so the view
    /// only offers it for one, and the progress is reported so a large file does not look
    /// stalled.
    func download(_ entry: HyperBackupEntry, to destination: URL) async -> DSMOperationOutcome {
        guard !entry.isFolder, !isDownloading else { return .cancelled }
        isDownloading = true
        downloadProgress = nil
        defer {
            isDownloading = false
            downloadProgress = nil
        }
        await OperationNotifier.prepare()

        let taskID = task.taskID
        let versionID = version.versionID
        let currentNode = node
        let outcome: DSMOperationOutcome
        do {
            try await session.withClient { client in
                try await client.downloadFromHyperBackup(
                    taskID: taskID,
                    versionID: versionID,
                    node: currentNode,
                    sourcePath: entry.path,
                    fileName: entry.name,
                    to: destination,
                    progress: { [weak self] progress in
                        Task { @MainActor in self?.downloadProgress = progress }
                    }
                )
            }
            outcome = .success(String(localized: "hyper_backup.restore.download.announcement", defaultValue: "\(entry.name) downloaded"))
        } catch {
            outcome = DSMError.isCancellation(error)
                ? .cancelled
                : .failure(String(localized: "hyper_backup.restore.download.error", defaultValue: "Downloading \(entry.name) failed: \(reason(for: error))"))
        }
        await OperationNotifier.signalCompletion(of: outcome, title: String(localized: "common.operation.download"))
        return outcome
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let folderCount = entries.count(where: \.isFolder)
        let fileCount = entries.count - folderCount
        return String(localized: "hyper_backup.restore.summary", defaultValue: "\(folderCount) folders, \(fileCount) files in \(locationDescription)")
    }

    private func successMessage(
        for selection: [HyperBackupEntry],
        destination: String
    ) -> String {
        guard let single = selection.first, selection.count == 1 else {
            return String(localized: "hyper_backup.restore.announcement.several", defaultValue: "\(selection.count) items restored to \(destination)")
        }
        return String(localized: "hyper_backup.restore.announcement.one", defaultValue: "\(single.name) restored to \(destination)")
    }

    /// Error 4462 is what the engine answers when everything asked for is already sitting in
    /// the destination and overwriting was declined. Reporting it as a plain failure would
    /// leave the user believing the restore ran.
    private func failureMessage(
        for error: Error,
        destination: String
    ) -> String {
        if case .apiError(let code) = error as? DSMError, code == 4462 {
            return String(localized: "hyper_backup.restore.error.nothing_copied", defaultValue: "Nothing was restored: \(destination) already holds these items, and replacing them was declined")
        }
        return String(localized: "hyper_backup.restore.error.failed", defaultValue: "Restore to \(destination) failed: \(reason(for: error))")
    }

    private func reason(for error: Error) -> String {
        (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}
