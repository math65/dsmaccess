//
//  ExternalDevicesViewModel.swift
//  dsmaccess
//
//  Lists external storage, ejects it, formats it and carries its shared settings.
//

import Foundation
import Observation

@MainActor
@Observable
final class ExternalDevicesViewModel {
    private(set) var devices: [ExternalStorageDevice] = []
    private(set) var settings: ExternalStorageSettings?
    private(set) var isLoading = false
    private(set) var busyDeviceIDs: Set<String> = []
    private(set) var isSavingSettings = false
    var errorMessage: String?
    /// Result of the last completed operation, kept on screen until the next one: an
    /// announcement alone is lost when the app is in the background.
    private(set) var lastOutcome: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    var hasDevices: Bool { !devices.isEmpty }

    /// True while DSM reports a format in progress on any device, which is what tells the
    /// interface to keep polling.
    var isFormattingAnyDevice: Bool {
        devices.contains { $0.isFormatting }
    }

    func isBusy(_ device: ExternalStorageDevice) -> Bool {
        busyDeviceIDs.contains(device.devID) || device.isFormatting
    }

    /// Reads the devices, and the settings alongside them on the first load.
    ///
    /// `announcesResult` stays false for background refreshes: VoiceOver must not comment on
    /// a poll the user did not ask for.
    func load(announcesResult: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let loaded = try await session.withClient { client in
                let devices = try await client.externalStorageDevices()
                let settings = try await client.externalStorageSettings()
                return (devices, settings)
            }
            guard generation == loadGeneration else { return }
            devices = loaded.0
            settings = loaded.1
            if announcesResult {
                VoiceOver.announce(deviceCountSummary, category: .result)
            }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = Self.description(of: error)
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }

    var deviceCountSummary: String {
        devices.isEmpty
            ? String(localized: "external_devices.summary.none")
            : String(
                localized: "external_devices.summary.count",
                defaultValue: "\(devices.count) external devices"
            )
    }

    func eject(_ device: ExternalStorageDevice) async {
        guard busyDeviceIDs.insert(device.devID).inserted else { return }
        defer { busyDeviceIDs.remove(device.devID) }
        let name = device.displayName
        do {
            try await session.withClient { try await $0.ejectExternalStorage(device) }
            await load()
            report(
                String(
                    localized: "external_devices.eject.success",
                    defaultValue: "\(name) ejected. You can unplug it."
                ),
                category: .result
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            await load()
            // A mutation whose answer never came back is not a mutation that failed: on a busy
            // NAS the request can time out after DSM has already ejected the drive. Announcing
            // a failure while the device is gone sends the user hunting a problem that is not
            // there — and the mutation must never be replayed to find out.
            guard devices.contains(where: { $0.devID == device.devID }) else {
                report(
                    String(
                        localized: "external_devices.eject.success",
                        defaultValue: "\(name) ejected. You can unplug it."
                    ),
                    category: .result
                )
                return
            }
            report(
                String(
                    localized: "external_devices.eject.error",
                    defaultValue: "Could not eject \(name): \(Self.description(of: error))"
                ),
                category: .error
            )
        }
    }

    func format(
        _ device: ExternalStorageDevice,
        as fileSystem: ExternalStorageFileSystem
    ) async {
        guard busyDeviceIDs.insert(device.devID).inserted else { return }
        defer { busyDeviceIDs.remove(device.devID) }
        let name = device.displayName
        do {
            try await session.withClient {
                try await $0.formatExternalStorage(device, as: fileSystem)
            }
            await load()
            // DSM answers as soon as it has started: the device now reports the "formating"
            // status, and the screen follows it from there.
            report(
                String(
                    localized: "external_devices.format.started",
                    defaultValue: "Formatting \(name) in \(fileSystem.title)"
                ),
                category: .progress
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            await load()
            // Same reasoning as ejection: if the device now reports "formating", DSM took the
            // request whatever the transport said, and the screen follows it from there.
            guard devices.first(where: { $0.devID == device.devID })?.isFormatting != true else {
                report(
                    String(
                        localized: "external_devices.format.started",
                        defaultValue: "Formatting \(name) in \(fileSystem.title)"
                    ),
                    category: .progress
                )
                return
            }
            report(
                String(
                    localized: "external_devices.format.error",
                    defaultValue: "Could not format \(name): \(Self.description(of: error))"
                ),
                category: .error
            )
        }
    }

    func updateSettings(_ updated: ExternalStorageSettings) async {
        guard !isSavingSettings else { return }
        isSavingSettings = true
        defer { isSavingSettings = false }
        let previous = settings
        settings = updated
        do {
            try await session.withClient { try await $0.updateExternalStorageSettings(updated) }
            report(String(localized: "external_devices.settings.saved"), category: .result)
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            // Put the switches back where DSM still has them, so the screen never shows a
            // setting the NAS did not accept.
            settings = previous
            report(
                String(
                    localized: "external_devices.settings.error",
                    defaultValue: "Could not save the settings: \(Self.description(of: error))"
                ),
                category: .error
            )
        }
    }

    /// Follows a running format to its end.
    ///
    /// DSM fills no progress field, so the only signal is `status` leaving "formating". The
    /// poll stays silent — announcing every three seconds would talk over the user — and says
    /// one thing only, when the device comes back.
    func followFormatting() async {
        guard isFormattingAnyDevice else { return }
        while isFormattingAnyDevice {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            await load()
        }
        report(String(localized: "external_devices.format.finished"), category: .result)
    }

    func dismissOutcome() {
        lastOutcome = nil
    }

    private func report(_ message: String, category: AnnouncementCategory) {
        lastOutcome = message
        VoiceOver.announce(message, category: category, priority: category == .error ? .high : .normal)
    }

    private static func description(of error: Error) -> String {
        (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}
