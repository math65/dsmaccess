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
                    ? String(localized: "alarm.rule.turned_on.announcement", defaultValue: "Rule turned on: \(description(of: rule))")
                    : String(localized: "alarm.rule.turned_off.announcement", defaultValue: "Rule turned off: \(description(of: rule))")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "alarm.rule.toggle.error", defaultValue: "Could not change the rule state: \(reason)"))
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
                return .success(String(localized: "alarm.rule.deleted.announcement", defaultValue: "Rule deleted: \(description(of: only))"))
            }
            return .success(String(localized: "alarm.rules.delete.announcement", defaultValue: "\(selection.count) rules deleted"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.delete_failed", defaultValue: "Delete failed: \(reason)"))
        }
    }

    func save(_ draft: PerformanceAlarmRuleDraft) async -> DSMOperationOutcome {
        do {
            try await session.withClient { try await $0.savePerformanceAlarmRule(draft) }
            await load()
            return .success(
                draft.isCreation
                    ? String(localized: "alarm.rule.created.announcement")
                    : String(localized: "alarm.rule.updated.announcement")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            // Le NAS identifie une règle par son type, sa cible, sa ressource et sa gravité :
            // deux règles qui les partagent entrent en collision, quel que soit leur seuil.
            if case .apiError(Self.ruleAlreadyExistsCode)? = error as? DSMError {
                return .failure(
                    String(localized: "alarm.rule.error.duplicate")
                )
            }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "common.error.save_failed", defaultValue: "Saving failed: \(reason)"))
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
            return String(localized: "alarm.rule.summary.processor", defaultValue: "Processor above \(threshold) %")
        case (.system, .loadAverageOneMinute):
            return String(localized: "alarm.rule.summary.load_average_1m", defaultValue: "1-minute load average above \(threshold)")
        case (.system, .loadAverageFiveMinutes):
            return String(localized: "alarm.rule.summary.load_average_5m", defaultValue: "5-minute load average above \(threshold)")
        case (.system, .loadAverageFifteenMinutes):
            return String(localized: "alarm.rule.summary.load_average_15m", defaultValue: "15-minute load average above \(threshold)")
        case (.system, .memory):
            return String(localized: "alarm.rule.summary.memory_usage", defaultValue: "Memory above \(threshold) %")
        case (.system, .graphicsUsage):
            return String(localized: "alarm.rule.summary.graphics_processor", defaultValue: "Graphics processor above \(threshold) %")
        case (.service, .processorUsage):
            return String(localized: "alarm.rule.summary.processor_target", defaultValue: "\(targetName(of: rule)): processor above \(threshold) %")
        case (.service, .memory):
            return String(localized: "alarm.rule.summary.memory_used_target", defaultValue: "\(targetName(of: rule)): memory above \(threshold) MB")
        case (.service, .diskActivity):
            return String(localized: "alarm.rule.summary.disk_throughput_target", defaultValue: "\(targetName(of: rule)): disk activity above \(threshold) MB/s")
        case (.volume, .diskActivity):
            return String(localized: "alarm.rule.summary.disk_usage_target", defaultValue: "\(targetName(of: rule)): disk activity above \(threshold) %")
        case (.iSCSI, .networkLatency):
            return String(localized: "alarm.rule.summary.network_latency_target", defaultValue: "\(targetName(of: rule)): network latency above \(threshold) ms")
        case (.iSCSI, .ioLatency):
            return String(localized: "alarm.rule.summary.access_latency_target", defaultValue: "\(targetName(of: rule)): access latency above \(threshold) ms")
        case (.internalUse, .rootPartition):
            return String(localized: "alarm.rule.summary.system_partition", defaultValue: "System partition above \(threshold) %")
        case (.internalUse, .temporaryDirectory):
            return String(localized: "alarm.rule.summary.temporary_folder", defaultValue: "Temporary folder above \(threshold) %")
        case (.internalUse, .coredumpCount):
            return String(localized: "alarm.rule.summary.core_dump_files", defaultValue: "More than \(threshold) core dump files")
        default:
            // Le NAS a renvoyé une combinaison que son propre client ne propose pas : la règle
            // reste listée et supprimable, avec ce qu'on sait d'elle.
            return String(localized: "alarm.rule.summary.unknown_resource", defaultValue: "Threshold of \(threshold) on an unknown resource")
        }
    }

    /// Le nom de la cible tel qu'il a été choisi dans le formulaire, quand la liste des
    /// services permet de le retrouver : le NAS renvoie parfois une clé de catalogue à la
    /// place, et lire « synobackupd » après avoir choisi « Backup service » dérouterait.
    private func targetName(of rule: PerformanceAlarmRule) -> String {
        if rule.kind == .service, let label = serviceLabels[rule.target] {
            return label
        }
        return rule.displayTarget ?? String(localized: "alarm.target.unknown")
    }

    func kindText(_ kind: PerformanceAlarmRule.Kind) -> String {
        switch kind {
        case .system: String(localized: "common.label.system")
        case .service: String(localized: "common.column.service")
        case .iSCSI: String(localized: "alarm.target.iscsi_lun")
        case .volume: String(localized: "common.column.volume")
        case .internalUse: String(localized: "alarm.target.internal_use")
        }
    }

    func severityText(_ severity: PerformanceAlarmRule.Severity) -> String {
        switch severity {
        case .warning: String(localized: "common.level.warning")
        case .critical: String(localized: "common.level.critical")
        }
    }

    func resourceText(_ resource: PerformanceAlarmRule.Resource, for kind: PerformanceAlarmRule.Kind) -> String {
        switch (kind, resource) {
        case (_, .processorUsage): String(localized: "alarm.resource.processor_usage")
        case (_, .loadAverageOneMinute): String(localized: "alarm.resource.load_average_1m")
        case (_, .loadAverageFiveMinutes): String(localized: "alarm.resource.load_average_5m")
        case (_, .loadAverageFifteenMinutes): String(localized: "alarm.resource.load_average_15m")
        case (.service, .memory): String(localized: "alarm.resource.memory_used")
        case (_, .memory): String(localized: "alarm.resource.memory_usage")
        case (.volume, .diskActivity): String(localized: "alarm.resource.disk_access_usage")
        case (_, .diskActivity): String(localized: "alarm.resource.disk_throughput")
        case (_, .networkLatency): String(localized: "alarm.resource.network_latency")
        case (_, .ioLatency): String(localized: "alarm.resource.access_latency")
        case (_, .rootPartition): String(localized: "alarm.resource.system_partition")
        case (_, .temporaryDirectory): String(localized: "alarm.resource.temporary_folder")
        case (_, .coredumpCount): String(localized: "alarm.resource.core_dump_files")
        case (_, .graphicsUsage): String(localized: "alarm.resource.graphics_processor_usage")
        }
    }

    /// L'unité écrite à côté du champ de seuil. Vide quand la grandeur n'en a pas : une charge
    /// moyenne ou un décompte se lisent sans unité.
    func unitText(_ unit: PerformanceAlarmRule.Unit) -> String {
        switch unit {
        case .percent: "%"
        case .megabytes: String(localized: "alarm.unit.megabytes")
        case .megabytesPerSecond: String(localized: "alarm.unit.megabytes_per_second")
        case .milliseconds: String(localized: "alarm.unit.milliseconds")
        case .none: ""
        }
    }

    func canModify(_ rule: PerformanceAlarmRule) -> Bool {
        rule.kind.isEditable && !busyIDs.contains(rule.id)
    }

    func isBusy(_ rule: PerformanceAlarmRule) -> Bool { busyIDs.contains(rule.id) }

    var summary: String {
        if let errorMessage { return errorMessage }
        if rules.isEmpty { return String(localized: "common.empty.alarm_rules") }
        let active = rules.filter(\.isEnabled).count
        return String(localized: "alarm.rules.summary", defaultValue: "\(rules.count) alarm rules, \(active) on")
    }
}
