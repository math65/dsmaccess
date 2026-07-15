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

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            settings = try await session.withClient { try await $0.packageSettings() }
        } catch {
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func setAutoUpdateMode(_ mode: AutoUpdateMode) async -> String {
        await apply { $0.setAutoUpdateMode(mode) }
    }

    func setBeta(_ enabled: Bool) async -> String {
        await apply { $0.updateChannelBeta = enabled }
    }

    func setDsmNotify(_ enabled: Bool) async -> String {
        await apply { $0.enableDsm = enabled }
    }

    func setEmailNotify(_ enabled: Bool) async -> String {
        await apply { $0.enableEmail = enabled }
    }

    /// Applique une mutation aux réglages chargés, enregistre l'objet complet, et renvoie le
    /// message à annoncer à VoiceOver.
    private func apply(_ mutate: (inout PackageSettings) -> Void) async -> String {
        guard var updated = settings else {
            return String(localized: "Réglages non chargés.")
        }
        mutate(&updated)
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.withClient { try await $0.setPackageSettings(updated) }
            settings = updated
            return String(localized: "Réglage enregistré")
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return String(localized: "Échec de l'enregistrement : \(reason)")
        }
    }
}
