//
//  OpenedFilesViewModel.swift
//  dsmaccess
//
//  “Open files” tab of the resource monitor: which files the NAS currently holds open, and
//  for whom. Useful before unmounting a volume or stopping a service — and to answer
//  “who is locking this file?”.
//

import Foundation
import Observation

@MainActor
@Observable
final class OpenedFilesViewModel {
    /// A busy NAS can hold hundreds of files open. The requested page is large but bounded,
    /// and the screen states what it is not showing rather than truncating silently.
    static let pageLimit = 500

    private(set) var files: [OpenedFile] = []
    /// Total returned by the NAS, which can exceed what has been loaded.
    private(set) var totalCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if files.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page = try await session.withClient {
                try await $0.openedFiles(limit: Self.pageLimit)
            }
            guard generation == loadGeneration else { return }
            // Stable initial order, by service then by path: the NAS returns the files in an
            // order of its own that changes from one call to the next. The visible sort
            // remains the one the user picks on the headers.
            files = page.files.sorted { lhs, rhs in
                let leftService = lhs.sortableService
                let rightService = rhs.sortableService
                if leftService != rightService {
                    return leftService.localizedStandardCompare(rightService) == .orderedAscending
                }
                return lhs.sortableName.localizedStandardCompare(rhs.sortableName) == .orderedAscending
            }
            totalCount = page.total ?? files.count
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    /// A local NAS service has neither an account nor an originating machine: the dash states
    /// the absence, where repeating the service name would look like actual data.
    func accountText(for file: OpenedFile) -> String { file.account ?? "—" }
    func hostText(for file: OpenedFile) -> String { file.host ?? "—" }
    func serviceText(for file: OpenedFile) -> String {
        file.service ?? String(localized: "opened_files.service.unknown")
    }
    func folderText(for file: OpenedFile) -> String { file.folder ?? "—" }

    /// True when the NAS holds more of them than what has been loaded.
    var isTruncated: Bool { totalCount > files.count }

    var summary: String {
        if let errorMessage { return errorMessage }
        if isTruncated {
            return String(localized: "opened_files.filtered_count.summary", defaultValue: "\(files.count) of \(totalCount) open files shown")
        }
        return String(localized: "opened_files.count.summary", defaultValue: "\(files.count) open files")
    }
}
