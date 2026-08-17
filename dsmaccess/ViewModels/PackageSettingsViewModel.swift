//
//  PackageSettingsViewModel.swift
//  dsmaccess
//
//  Loads and changes the global Package Center settings (SYNO.Core.Package.Setting).
//  Every change saves the whole object (the `set` API requires it) and returns an already
//  localized message to announce to VoiceOver, like FileServicesViewModel.
//

import Foundation
import Observation

@MainActor
@Observable
final class PackageSettingsViewModel {
    private(set) var settings: PackageSettings?
    private(set) var isLoading = false
    /// True while a setting is being saved (controls are disabled for the duration of the call).
    private(set) var isSaving = false
    var errorMessage: String?
    var saveErrorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0
    /// What each package is already set to. DSM does not return the custom lists from `get`,
    /// so switching to the per-package strategy has to send back what the packages
    /// themselves reported, or it would silently clear every choice.
    private let selection: PackageAutoUpdateSelection

    init(session: SessionStore, selection: PackageAutoUpdateSelection = .init()) {
        self.session = session
        self.selection = selection
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { try await $0.packageSettings() }
            guard generation == loadGeneration else { return }
            settings = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setAutoUpdateMode(_ mode: AutoUpdateMode) async -> DSMOperationOutcome {
        await apply { $0.setAutoUpdateMode(mode) }
    }

    func setBeta(_ enabled: Bool) async -> DSMOperationOutcome {
        await apply { $0.updateChannelBeta = enabled }
    }

    func setDsmNotify(_ enabled: Bool) async -> DSMOperationOutcome {
        await apply { $0.enableDsm = enabled }
    }

    func setEmailNotify(_ enabled: Bool) async -> DSMOperationOutcome {
        await apply { $0.enableEmail = enabled }
    }

    /// Applies a mutation to the loaded settings, saves the whole object, and returns the
    /// message to announce to VoiceOver.
    private func apply(_ mutate: (inout PackageSettings) -> Void) async -> DSMOperationOutcome {
        guard var updated = settings else {
            return .failure(String(localized: "packages.settings.not_loaded.error"))
        }
        mutate(&updated)
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let selection = selection
            try await session.withClient {
                try await $0.setPackageSettings(updated, selection: selection)
            }
            settings = updated
            return .success(String(localized: "packages.settings.save.success"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            let message = String(localized: "packages.settings.save.error", defaultValue: "Failed to save: \(reason)")
            saveErrorMessage = message
            return .failure(message)
        }
    }
}
