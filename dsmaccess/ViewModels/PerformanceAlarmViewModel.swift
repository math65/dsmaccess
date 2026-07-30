//
//  PerformanceAlarmViewModel.swift
//  dsmaccess
//
//  Onglet Alarme des performances : les seuils au-delà desquels le NAS consigne une alerte
//  dans son historique. Sans règle, ce journal reste vide quoi qu'il arrive — c'est cet écran
//  qui lui donne quelque chose à enregistrer.
//

import Foundation
import Observation

@MainActor
@Observable
final class PerformanceAlarmViewModel {
    private(set) var rules: [PerformanceAlarmRule] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// Règles dont une bascule ou une suppression est en cours, pour désarmer leurs commandes.
    private(set) var busyIDs: Set<String> = []
    /// Le NAS autorise les règles d'usage interne, réservées à Synology. Lu pour ne pas
    /// masquer une règle que le NAS afficherait.
    private(set) var supportsInternalUse = false

    /// Cibles proposées par le formulaire, chargées à l'ouverture de la feuille seulement :
    /// elles ne servent à rien tant qu'on ne compose pas de règle.
    private(set) var services: [Target] = []
    private(set) var volumes: [Target] = []
    private(set) var isLoadingTargets = false

    /// Une cible choisissable : ce que le NAS attend, et ce que l'utilisateur lit.
    struct Target: Identifiable, Sendable, Equatable {
        let value: String
        let label: String

        var id: String { value }
    }

    /// Libellé lisible de chaque service, retrouvé par nom d'unité. Le NAS renvoie parfois,
    /// dans la règle, une clé de son propre catalogue à la place du nom : la liste des
    /// services, elle, porte le libellé que l'utilisateur a choisi dans le formulaire.
    private var serviceLabels: [String: String] = [:]

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if rules.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page = try await session.withClient { try await $0.performanceAlarmRules() }
            guard generation == loadGeneration else { return }

            // Les libellés de service sont résolus **avant** de publier les règles : le
            // tableau doit apparaître nommé, et non se renommer sous les doigts de
            // l'utilisateur une fraction de seconde plus tard. Leur absence n'est pas une
            // erreur — le nom d'unité reste lisible.
            if page.rules.contains(where: { $0.kind == .service }), serviceLabels.isEmpty {
                let loaded = await loadServices()
                guard generation == loadGeneration else { return }
                services = loaded
                serviceLabels = Dictionary(
                    loaded.map { ($0.value, $0.label) },
                    uniquingKeysWith: { first, _ in first }
                )
            }

            // Ordre de départ stable : les règles critiques d'abord, puis par cible. Le tri
            // visible reste celui que l'utilisateur choisit sur les en-têtes.
            rules = page.rules.sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity.rawValue > rhs.severity.rawValue }
                return lhs.sortableTarget.localizedStandardCompare(rhs.sortableTarget) == .orderedAscending
            }
            supportsInternalUse = page.supportsInternalUse
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    /// Active ou coupe une règle. Le NAS accepte un lot ; une seule règle à la fois suffit ici
    /// et rend le résultat annonçable sans ambiguïté.
    func setEnabled(_ rule: PerformanceAlarmRule, _ enabled: Bool) async -> DSMOperationOutcome {
        busyIDs.insert(rule.id)
        defer { busyIDs.remove(rule.id) }
        do {
            try await session.withClient {
                try await $0.setPerformanceAlarmRules([(id: rule.id, enabled: enabled)])
            }
            await load()
            return .success(
                enabled
                    ? String(localized: "Règle activée : \(description(of: rule))")
                    : String(localized: "Règle désactivée : \(description(of: rule))")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec du changement d’état : \(reason)"))
        }
    }

    func delete(_ selection: [PerformanceAlarmRule]) async -> DSMOperationOutcome {
        guard !selection.isEmpty else { return .cancelled }
        let ids = selection.map(\.id)
        busyIDs.formUnion(ids)
        defer { busyIDs.subtract(ids) }
        do {
            try await session.withClient { try await $0.deletePerformanceAlarmRules(ids: ids) }
            await load()
            if selection.count == 1, let only = selection.first {
                return .success(String(localized: "Règle supprimée : \(description(of: only))"))
            }
            return .success(String(localized: "\(selection.count) règles supprimées"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec de la suppression : \(reason)"))
        }
    }

    func save(_ draft: PerformanceAlarmRuleDraft) async -> DSMOperationOutcome {
        do {
            try await session.withClient { try await $0.savePerformanceAlarmRule(draft) }
            await load()
            return .success(
                draft.isCreation
                    ? String(localized: "Règle créée")
                    : String(localized: "Règle modifiée")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            // Le NAS identifie une règle par son type, sa cible, sa ressource et sa gravité :
            // deux règles qui les partagent entrent en collision, quel que soit leur seuil.
            if case .apiError(Self.ruleAlreadyExistsCode)? = error as? DSMError {
                return .failure(
                    String(localized: "Une règle surveille déjà cette ressource avec la même gravité. Modifiez la règle existante ou changez la gravité.")
                )
            }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec de l’enregistrement : \(reason)"))
        }
    }

    /// Code renvoyé par le NAS quand le quadruplet identifiant la règle est déjà pris.
    private static let ruleAlreadyExistsCode = 6106

    /// Charge les cibles choisissables. Les deux lectures sont indépendantes : un NAS sans
    /// volume lisible doit quand même pouvoir composer une règle de service, et l'inverse.
    func loadTargets() async {
        isLoadingTargets = true
        defer { isLoadingTargets = false }
        if services.isEmpty { services = await loadServices() }
        volumes = await loadVolumes()
    }

    private func loadServices() async -> [Target] {
        do {
            let groups = try await session.withClient { try await $0.processGroups() }
            return groups
                .compactMap { group in
                    // DSM écarte sa propre tranche interne de la liste des services
                    // surveillables ; elle ne désigne rien que l'utilisateur reconnaîtrait.
                    guard let unitName = group.unitName, unitName != Self.internalSlice else {
                        return nil
                    }
                    return Target(value: unitName, label: group.displayName)
                }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        } catch {
            return []
        }
    }

    private func loadVolumes() async -> [Target] {
        do {
            let storage = try await session.withClient { try await $0.storageInfo() }
            return (storage.volumes ?? []).compactMap { volume in
                guard let path = volume.mountPath, !path.isEmpty else { return nil }
                return Target(value: path, label: volume.desc?.isEmpty == false ? volume.desc! : path)
            }
        } catch {
            return []
        }
    }

    /// Tranche que DSM exclut lui-même des services surveillables.
    private static let internalSlice = "syno_dsm_internal.slice"

    // MARK: - Présentation

    /// La règle en une phrase, telle qu'elle se lit dans le tableau et s'annonce après une
    /// action. Une clé complète par cas plutôt qu'un assemblage de fragments : l'ordre des
    /// mots n'est pas le même d'une langue à l'autre.
    func description(of rule: PerformanceAlarmRule) -> String {
        let threshold = rule.threshold
        switch (rule.kind, rule.resource) {
        case (.system, .processorUsage):
            return String(localized: "Processeur au-dessus de \(threshold) %")
        case (.system, .loadAverageOneMinute):
            return String(localized: "Charge moyenne sur 1 minute au-dessus de \(threshold)")
        case (.system, .loadAverageFiveMinutes):
            return String(localized: "Charge moyenne sur 5 minutes au-dessus de \(threshold)")
        case (.system, .loadAverageFifteenMinutes):
            return String(localized: "Charge moyenne sur 15 minutes au-dessus de \(threshold)")
        case (.system, .memory):
            return String(localized: "Mémoire au-dessus de \(threshold) %")
        case (.system, .graphicsUsage):
            return String(localized: "Processeur graphique au-dessus de \(threshold) %")
        case (.service, .processorUsage):
            return String(localized: "\(targetName(of: rule)) : processeur au-dessus de \(threshold) %")
        case (.service, .memory):
            return String(localized: "\(targetName(of: rule)) : mémoire au-dessus de \(threshold) Mo")
        case (.service, .diskActivity):
            return String(localized: "\(targetName(of: rule)) : activité disque au-dessus de \(threshold) Mo/s")
        case (.volume, .diskActivity):
            return String(localized: "\(targetName(of: rule)) : activité disque au-dessus de \(threshold) %")
        case (.iSCSI, .networkLatency):
            return String(localized: "\(targetName(of: rule)) : latence réseau au-dessus de \(threshold) ms")
        case (.iSCSI, .ioLatency):
            return String(localized: "\(targetName(of: rule)) : latence d’accès au-dessus de \(threshold) ms")
        case (.internalUse, .rootPartition):
            return String(localized: "Partition système au-dessus de \(threshold) %")
        case (.internalUse, .temporaryDirectory):
            return String(localized: "Dossier temporaire au-dessus de \(threshold) %")
        case (.internalUse, .coredumpCount):
            return String(localized: "Plus de \(threshold) fichiers de vidage mémoire")
        default:
            // Le NAS a renvoyé une combinaison que son propre client ne propose pas : la règle
            // reste listée et supprimable, avec ce qu'on sait d'elle.
            return String(localized: "Seuil de \(threshold) sur une ressource inconnue")
        }
    }

    /// Le nom de la cible tel qu'il a été choisi dans le formulaire, quand la liste des
    /// services permet de le retrouver : le NAS renvoie parfois une clé de catalogue à la
    /// place, et lire « synobackupd » après avoir choisi « Backup service » dérouterait.
    private func targetName(of rule: PerformanceAlarmRule) -> String {
        if rule.kind == .service, let label = serviceLabels[rule.target] {
            return label
        }
        return rule.displayTarget ?? String(localized: "Cible inconnue")
    }

    func kindText(_ kind: PerformanceAlarmRule.Kind) -> String {
        switch kind {
        case .system: String(localized: "Système")
        case .service: String(localized: "Service")
        case .iSCSI: String(localized: "LUN iSCSI")
        case .volume: String(localized: "Volume")
        case .internalUse: String(localized: "Usage interne")
        }
    }

    func severityText(_ severity: PerformanceAlarmRule.Severity) -> String {
        switch severity {
        case .warning: String(localized: "Avertissement")
        case .critical: String(localized: "Critique")
        }
    }

    func resourceText(_ resource: PerformanceAlarmRule.Resource, for kind: PerformanceAlarmRule.Kind) -> String {
        switch (kind, resource) {
        case (_, .processorUsage): String(localized: "Utilisation du processeur")
        case (_, .loadAverageOneMinute): String(localized: "Charge moyenne sur 1 minute")
        case (_, .loadAverageFiveMinutes): String(localized: "Charge moyenne sur 5 minutes")
        case (_, .loadAverageFifteenMinutes): String(localized: "Charge moyenne sur 15 minutes")
        case (.service, .memory): String(localized: "Mémoire occupée")
        case (_, .memory): String(localized: "Utilisation de la mémoire")
        case (.volume, .diskActivity): String(localized: "Utilisation des accès disque")
        case (_, .diskActivity): String(localized: "Débit disque")
        case (_, .networkLatency): String(localized: "Latence réseau")
        case (_, .ioLatency): String(localized: "Latence d’accès")
        case (_, .rootPartition): String(localized: "Partition système")
        case (_, .temporaryDirectory): String(localized: "Dossier temporaire")
        case (_, .coredumpCount): String(localized: "Fichiers de vidage mémoire")
        case (_, .graphicsUsage): String(localized: "Utilisation du processeur graphique")
        }
    }

    /// L'unité écrite à côté du champ de seuil. Vide quand la grandeur n'en a pas : une charge
    /// moyenne ou un décompte se lisent sans unité.
    func unitText(_ unit: PerformanceAlarmRule.Unit) -> String {
        switch unit {
        case .percent: "%"
        case .megabytes: String(localized: "Mo")
        case .megabytesPerSecond: String(localized: "Mo/s")
        case .milliseconds: String(localized: "ms")
        case .none: ""
        }
    }

    func canModify(_ rule: PerformanceAlarmRule) -> Bool {
        rule.kind.isEditable && !busyIDs.contains(rule.id)
    }

    func isBusy(_ rule: PerformanceAlarmRule) -> Bool { busyIDs.contains(rule.id) }

    var summary: String {
        if let errorMessage { return errorMessage }
        if rules.isEmpty { return String(localized: "Aucune règle d’alarme") }
        let active = rules.filter(\.isEnabled).count
        return String(localized: "\(rules.count) règles d’alarme, \(active) actives")
    }
}
