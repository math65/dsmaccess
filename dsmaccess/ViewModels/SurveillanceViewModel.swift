//
//  SurveillanceViewModel.swift
//  dsmaccess
//
//  État, activation et instantanés des caméras.
//

import Foundation
import Observation

@MainActor
@Observable
final class SurveillanceViewModel {
    private(set) var cameras: [SurveillanceCamera] = []
    private(set) var snapshotData: Data?
    private(set) var snapshotCameraID: String?
    private(set) var isLoading = false
    private(set) var isLoadingSnapshot = false
    private(set) var busyIDs: Set<String> = []
    var errorMessage: String?
    var snapshotErrorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0
    private var snapshotGeneration = 0

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
            let result = try await session.withClient { try await $0.listSurveillanceCameras() }.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            guard generation == loadGeneration else { return }
            cameras = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, ids: Set<String>) async -> String {
        guard !ids.isEmpty else { return String(localized: "Aucune caméra sélectionnée") }
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }

        do {
            try await session.withClient {
                try await $0.setSurveillanceCameras(ids: ids, enabled: enabled)
            }
            await load(silently: true)
            return enabled
                ? String(localized: "\(ids.count) caméras activées")
                : String(localized: "\(ids.count) caméras désactivées")
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec de l’opération : \(reason)")
        }
    }

    func loadSnapshot(for camera: SurveillanceCamera) async {
        snapshotGeneration += 1
        let generation = snapshotGeneration
        isLoadingSnapshot = true
        snapshotErrorMessage = nil
        snapshotCameraID = camera.id
        defer { if generation == snapshotGeneration { isLoadingSnapshot = false } }

        do {
            let data = try await session.withClient {
                try await $0.surveillanceSnapshot(cameraID: camera.id)
            }
            guard generation == snapshotGeneration, snapshotCameraID == camera.id else { return }
            snapshotData = data
        } catch {
            guard generation == snapshotGeneration,
                  snapshotCameraID == camera.id,
                  !DSMError.isCancellation(error) else { return }
            snapshotData = nil
            snapshotErrorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        let available = cameras.filter(\.isAvailable).count
        return String(localized: "\(cameras.count) caméras, \(available) disponibles")
    }
}
