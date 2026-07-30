//
//  ResourceMonitorHistoryViewModel.swift
//  dsmaccess
//
//  Onglet Historique du moniteur de ressources : les alertes que le NAS a enregistrées quand
//  une ressource a franchi un seuil.
//
//  Le journal ne se remplit que si l'enregistrement est actif, et DSM le laisse désactivé par
//  défaut. L'état du réglage est donc chargé avec les entrées : sans lui, un journal vide se
//  lirait comme un NAS sans le moindre incident.
//

import Foundation
import Observation

@MainActor
@Observable
final class ResourceMonitorHistoryViewModel {
    /// Le NAS conserve son journal aussi longtemps que l'enregistrement reste actif. La page
    /// est large mais bornée, et l'écran dit ce qu'il ne montre pas.
    static let pageLimit = 1000

    private(set) var entries: [ResourceMonitorLogEntry] = []
    /// Total renvoyé par le NAS, qui peut dépasser ce qui est chargé.
    private(set) var totalCount = 0
    /// `nil` tant que le réglage n'a pas été lu : l'écran ne conclut rien avant de savoir.
    private(set) var historyEnabled: Bool?
    /// Nombre de règles d'alarme, lu seulement quand le journal est vide. `nil` quand la
    /// question ne se pose pas ou que le NAS a refusé de répondre.
    private(set) var alarmRuleCount: Int?
    private(set) var isLoading = false
    /// Vrai le temps d'un changement du réglage, pour désarmer l'interrupteur.
    private(set) var isUpdatingSetting = false
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if entries.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let enabled = try await session.withClient {
                try await $0.resourceMonitorHistoryEnabled()
            }
            let page = try await session.withClient {
                try await $0.resourceMonitorLogs(limit: Self.pageLimit)
            }
            guard generation == loadGeneration else { return }
            historyEnabled = enabled
            // Ordre de départ stable, de l'alerte la plus récente à la plus ancienne, comme
            // DSM. Le tri visible reste celui que l'utilisateur choisit sur les en-têtes.
            entries = page.entries.sorted { $0.sortableDate > $1.sortableDate }
            totalCount = page.total ?? entries.count
            if entries.isEmpty, enabled {
                let count = await alarmRules()
                guard generation == loadGeneration else { return }
                alarmRuleCount = count
            } else {
                alarmRuleCount = nil
            }
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    /// Active ou coupe l'enregistrement de l'historique. Activer ne produit rien
    /// rétroactivement : le message le dit, pour que l'écran resté vide ne passe pas pour un
    /// réglage sans effet.
    func setHistoryEnabled(_ enabled: Bool) async -> DSMOperationOutcome {
        isUpdatingSetting = true
        defer { isUpdatingSetting = false }
        do {
            try await session.withClient {
                try await $0.setResourceMonitorHistory(enabled: enabled)
            }
            historyEnabled = enabled
            await load()
            return .success(
                enabled
                    ? String(localized: "Enregistrement de l’historique activé. Les alertes à venir y seront consignées.")
                    : String(localized: "Enregistrement de l’historique désactivé. Les alertes déjà consignées sont conservées.")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec du changement de réglage : \(reason)"))
        }
    }

    /// Le journal est vide : reste à savoir si c'est faute d'incident ou faute de règle
    /// capable d'en signaler un. L'échec de cette lecture n'est pas remonté comme une erreur
    /// de l'écran — le journal, lui, a bien été chargé, et l'état vide se contente alors du
    /// message général.
    private func alarmRules() async -> Int? {
        try? await session.withClient { try await $0.performanceAlarmRules().rules.count }
    }

    /// Horodatage rendu dans la langue du Mac. Un tiret quand DSM a envoyé une forme que nous
    /// n'avons pas su lire : l'alerte reste listée, sans date inventée.
    func dateText(for entry: ResourceMonitorLogEntry) -> String {
        guard let recordedAt = entry.recordedAt else { return "—" }
        return recordedAt.formatted(date: .abbreviated, time: .standard)
    }

    /// Gravité en toutes lettres. DSM envoie ses niveaux en anglais et les traduit dans son
    /// propre client ; une valeur inconnue est reprise telle quelle plutôt que rangée d'office
    /// dans un niveau existant.
    func levelText(for entry: ResourceMonitorLogEntry) -> String {
        switch entry.level {
        case .information: String(localized: "Information")
        case .warning: String(localized: "Avertissement")
        case .critical: String(localized: "Critique")
        case .other(let raw): raw.isEmpty ? String(localized: "Niveau inconnu") : raw
        }
    }

    func eventText(for entry: ResourceMonitorLogEntry) -> String {
        entry.event ?? String(localized: "Alerte sans description")
    }

    /// Vrai quand le NAS en conserve plus que ce qui a été chargé.
    var isTruncated: Bool { totalCount > entries.count }

    var summary: String {
        if let errorMessage { return errorMessage }
        if historyEnabled == false {
            return String(localized: "Enregistrement de l’historique désactivé")
        }
        if alarmRuleCount == 0 {
            return String(localized: "Aucune alerte enregistrée, aucune règle d’alarme définie")
        }
        if isTruncated {
            return String(localized: "\(entries.count) alertes affichées sur \(totalCount) enregistrées")
        }
        return String(localized: "\(entries.count) alertes enregistrées")
    }
}
