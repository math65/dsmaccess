//
//  SharesViewModel.swift
//  dsmaccess
//
//  Charge la liste des dossiers partagés (SYNO.Core.Share) et pilote leur création/suppression.
//  Les actions renvoient un message déjà localisé à annoncer à VoiceOver.
//

import Foundation
import Observation

@MainActor
@Observable
final class SharesViewModel {
    private(set) var shares: [SharedFolder] = []
    /// Chemins des volumes disponibles pour la création (« /volume1 »…).
    private(set) var volumes: [String] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await session.withClient { client in
                let shares = try await client.listSharedFolders().sorted {
                    ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending
                }
                let info: StorageInfo?
                do {
                    info = try await client.storageInfo()
                } catch DSMError.sessionExpired {
                    throw DSMError.sessionExpired
                } catch {
                    info = nil
                }
                return (shares, info)
            }
            shares = result.0
            if let info = result.1 {
                volumes = (info.volumes ?? [])
                    .compactMap { $0.numId.map { "/volume\($0)" } }
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            }
        } catch {
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Crée un dossier partagé. Renvoie le message à annoncer.
    func create(name: String, volumePath: String, description: String) async -> String {
        do {
            try await session.withClient {
                try await $0.createSharedFolder(
                    name: name,
                    volumePath: volumePath,
                    description: description
                )
            }
            await load()
            return String(localized: "Dossier partagé créé : \(name)")
        } catch {
            return String(localized: "Échec de la création : \(reason(for: error))")
        }
    }

    /// Supprime un dossier partagé. Renvoie le message à annoncer.
    func delete(_ folder: SharedFolder) async -> String {
        guard let name = folder.name else {
            return String(localized: "Identifiant du dossier partagé introuvable.")
        }
        do {
            try await session.withClient { try await $0.deleteSharedFolder(name: name) }
            await load()
            return String(localized: "Dossier partagé supprimé : \(name)")
        } catch {
            return String(localized: "Échec de la suppression : \(reason(for: error))")
        }
    }

    /// Résumé annoncé à VoiceOver une fois chargé.
    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(shares.count) dossiers partagés")
    }

    /// Message d'erreur, avec des cas amicaux pour les codes SYNO.Core.Share connus.
    private func reason(for error: Error) -> String {
        if case let DSMError.apiError(code) = error {
            switch code {
            case 3301: return String(localized: "un dossier partagé porte déjà ce nom")
            case 3309: return String(localized: "le nombre maximum de dossiers partagés est atteint")
            default: break
            }
        }
        return (error as? DSMError)?.errorDescription ?? error.localizedDescription
    }
}
