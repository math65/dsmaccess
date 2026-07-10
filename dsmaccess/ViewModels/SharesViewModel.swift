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
        guard let client = session.client, let sid = session.sid else {
            session.clear()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            shares = try await client.listSharedFolders(sid: sid).sorted {
                ($0.name ?? "").localizedStandardCompare($1.name ?? "") == .orderedAscending
            }
            // Volumes pour le sélecteur de création (réutilise l'API du module Stockage).
            // Le chemin d'un volume DSM suit son numéro : num_id 1 → « /volume1 ».
            if let info = try? await client.storageInfo(sid: sid) {
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
        guard let client = session.client, let sid = session.sid else {
            return String(localized: "Session expirée.")
        }
        do {
            try await client.createSharedFolder(name: name, volumePath: volumePath,
                                                 description: description, sid: sid)
            await load()
            return String(localized: "Dossier partagé créé : \(name)")
        } catch {
            return String(localized: "Échec de la création : \(reason(for: error))")
        }
    }

    /// Supprime un dossier partagé. Renvoie le message à annoncer.
    func delete(_ folder: SharedFolder) async -> String {
        guard let client = session.client, let sid = session.sid, let name = folder.name else {
            return String(localized: "Session expirée.")
        }
        do {
            try await client.deleteSharedFolder(name: name, sid: sid)
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
