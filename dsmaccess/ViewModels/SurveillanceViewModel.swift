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

    func setEnabled(_ enabled: Bool, ids: Set<String>) async -> DSMOperationOutcome {
        guard !ids.isEmpty else {
            return .failure(String(localized: "surveillance.camera.selection.empty"))
        }
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }

        do {
            try await session.withClient {
                try await $0.setSurveillanceCameras(ids: ids, enabled: enabled)
            }
            await load(silently: true)
            return .success(
                enabled
                    ? String(localized: "surveillance.camera.enable_selected.result", defaultValue: "\(ids.count) cameras enabled")
                    : String(localized: "surveillance.camera.disable_selected.result", defaultValue: "\(ids.count) cameras disabled")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.operation_failed", defaultValue: "The operation failed: \(reason)"))
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
        return String(localized: "surveillance.camera.count.summary", defaultValue: "\(cameras.count) cameras, \(available) available")
    }
}
