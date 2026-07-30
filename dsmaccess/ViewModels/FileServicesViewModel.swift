//
//  FileServicesViewModel.swift
//  dsmaccess
//
//  Loads the state of the file services (SMB, NFS, FTP and rsync) and drives their
//  enabling/disabling. Each service is queried independently: if one fails, the
//  others stay usable. The actions return an already localized message to be
//  announced to VoiceOver.
//

import Foundation
import Observation

/// Displayed state of a file service.
enum FileServiceState: Equatable {
    case on
    case off
    case unknown          // Flag missing from the response.
    case failed(String)   // network or API error
}

@MainActor
@Observable
final class FileServicesViewModel {
    /// Services displayed, in order.
    let services = FileService.allCases
    private(set) var states: [FileService: FileServiceState] = [:]
    private(set) var isLoading = false
    /// Services with a toggle in flight (button disabled for the duration of the call).
    private(set) var busy: Set<FileService> = []

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        var loadedStates: [FileService: FileServiceState] = [:]
        for service in services {
            loadedStates[service] = await fetch(service)
        }
        guard generation == loadGeneration else { return }
        states = loadedStates
    }

    /// Toggles a service. Returns the message to announce to VoiceOver.
    func setEnabled(_ service: FileService, _ enabled: Bool) async -> DSMOperationOutcome {
        busy.insert(service)
        defer { busy.remove(service) }
        do {
            try await session.withClient { try await $0.setFileService(service, enabled: enabled) }
            states[service] = await fetch(service)
            return .success(
                enabled
                    ? String(localized: "file_services.service.enabled.announcement", defaultValue: "\(service.displayName) enabled")
                    : String(localized: "file_services.service.disabled.announcement", defaultValue: "\(service.displayName) disabled")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            states[service] = await fetch(service)
            return .failure(String(localized: "common.error.failed_for_item", defaultValue: "Failed for \(service.displayName): \(reason)"))
        }
    }

    /// Summary announced once loading has finished.
    var summary: String {
        let on = states.values.filter { $0 == .on }.count
        return String(localized: "file_services.summary", defaultValue: "File services: \(on) of \(services.count) enabled")
    }

    var hasFailures: Bool {
        states.values.contains {
            if case .failed = $0 { true } else { false }
        }
    }

    private func fetch(_ service: FileService) async -> FileServiceState {
        do {
            switch try await session.withClient({ try await $0.fileServiceEnabled(service) }) {
            case true?: return .on
            case false?: return .off
            case nil: return .unknown
            }
        } catch {
            return .failed((error as? DSMError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
