//
//  PackageSettingsViewModel.swift
//  dsmaccess
//
//  Charge et modifie les réglages globaux du Centre de paquets (SYNO.Core.Package.Setting).
//  Chaque changement enregistre l'objet complet (l'API `set` l'exige) et renvoie un message
//  déjà localisé à annoncer à VoiceOver, comme FileServicesViewModel.
//

import Foundation
import Observation

@MainActor
@Observable
final class PackageSettingsViewModel {
    private(set) var settings: PackageSettings?
    private(set) var isLoading = false
    /// Vrai pendant l'enregistrement d'un réglage (contrôles désactivés le temps de l'appel).
    private(set) var isSaving = false
    var errorMessage: String?
    var saveErrorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
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

    /// Applique une mutation aux réglages chargés, enregistre l'objet complet, et renvoie le
    /// message à annoncer à VoiceOver.
    private func apply(_ mutate: (inout PackageSettings) -> Void) async -> DSMOperationOutcome {
        guard var updated = settings else {
            return .failure(String(localized: "Réglages non chargés."))
        }
        mutate(&updated)
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            try await session.withClient { try await $0.setPackageSettings(updated) }
            settings = updated
            return .success(String(localized: "Réglage enregistré"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            let message = String(localized: "Échec de l'enregistrement : \(reason)")
            saveErrorMessage = message
            return .failure(message)
        }
    }
}
