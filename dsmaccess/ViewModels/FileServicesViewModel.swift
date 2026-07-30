//
//  FileServicesViewModel.swift
//  dsmaccess
//
//  Charge l'état des services de fichiers (SMB, NFS, FTP et rsync) et pilote leur
//  activation/désactivation. Chaque service est interrogé indépendamment : si l'un
//  échoue, les autres restent utilisables. Les actions renvoient un message déjà
//  localisé à annoncer à VoiceOver.
//

import Foundation
import Observation

/// État affiché d'un service de fichiers.
enum FileServiceState: Equatable {
    case on
    case off
    case unknown          // Drapeau absent de la réponse.
    case failed(String)   // erreur réseau ou API
}

@MainActor
@Observable
final class FileServicesViewModel {
    /// Services affichés, dans l'ordre.
    let services = FileService.allCases
    private(set) var states: [FileService: FileServiceState] = [:]
    private(set) var isLoading = false
    /// Services dont une bascule est en cours (bouton désactivé le temps de l'appel).
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

    /// Bascule un service. Renvoie le message à annoncer à VoiceOver.
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

    /// Résumé annoncé une fois le chargement terminé.
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
