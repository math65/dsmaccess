//
//  TaskManagerViewModel.swift
//  dsmaccess
//
//  Gestionnaire des tâches du moniteur de ressources : les services regroupés comme DSM
//  les présente, et les processus les plus actifs. Comme pour les ressources, une
//  actualisation périodique reste SILENCIEUSE ; seule une actualisation manuelle annonce.
//

import Foundation
import Observation

@MainActor
@Observable
final class TaskManagerViewModel {
    /// Le NAS renvoie plus de trois cents processus. En afficher la totalité dans un
    /// formulaire serait illisible au clavier comme au lecteur d'écran : seuls les plus
    /// actifs sont montrés, et l'écran le dit au lieu de tronquer en silence.
    static let visibleProcessCount = 10

    private(set) var groups: [ProcessGroup] = []
    private(set) var processes: [SystemProcess] = []
    private(set) var totalProcessCount = 0
    private(set) var isLoading = false
    var errorMessage: String?

    var autoRefresh = false {
        didSet {
            guard autoRefresh != oldValue else { return }
            autoRefresh ? startAutoRefresh() : stopAutoRefresh(announce: true)
        }
    }

    private let session: SessionStore
    private var refreshTask: Task<Void, Never>?
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if groups.isEmpty && processes.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            // Les deux lectures sont indépendantes : les mener de front évite d'attendre
            // deux allers-retours là où le NAS peut répondre en parallèle.
            async let loadedGroups = session.withClient { try await $0.processGroups() }
            async let loadedProcesses = session.withClient { try await $0.processes() }
            let (fetchedGroups, fetchedProcesses) = try await (loadedGroups, loadedProcesses)
            guard generation == loadGeneration else { return }
            // Tri par mémoire et non par processeur : sur un NAS au repos tous les
            // services affichent « 0,0 % », et un tri sur des écarts invisibles donne une
            // liste qui paraît aléatoire — et qui se réordonne à chaque actualisation,
            // ce qui rend le parcours au lecteur d'écran impraticable.
            groups = fetchedGroups.sorted { lhs, rhs in
                let leftMemory = lhs.memoryBytes ?? -1
                let rightMemory = rhs.memoryBytes ?? -1
                if leftMemory != rightMemory { return leftMemory > rightMemory }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
            totalProcessCount = fetchedProcesses.count
            processes = Array(
                fetchedProcesses
                    .sorted { ($0.cpuPercent ?? -1) > ($1.cpuPercent ?? -1) }
                    .prefix(Self.visibleProcessCount)
            )
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    private func startAutoRefresh() {
        VoiceOver.announce(
            String(localized: "Actualisation automatique activée"),
            category: .automaticRefresh
        )
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                await self?.load()
            }
        }
    }

    private func stopAutoRefresh(announce: Bool) {
        refreshTask?.cancel()
        refreshTask = nil
        if announce {
            VoiceOver.announce(
                String(localized: "Actualisation automatique désactivée"),
                category: .automaticRefresh
            )
        }
    }

    func stop() { stopAutoRefresh(announce: false) }

    // MARK: - Affichage formaté

    /// « 12,4 %, 39,3 Mo, 3 processus ». Une mesure absente s'écrit « — » : DSM renvoie
    /// littéralement « - » pour les groupes qu'il ne mesure pas, et écrire zéro à la place
    /// ferait passer une absence pour une valeur.
    func activityText(for group: ProcessGroup) -> String {
        let cpu = group.cpuPercent
            .map { $0.formatted(.number.precision(.fractionLength(1))) + " %" } ?? "—"
        let memory = group.memoryBytes
            .map { $0.formatted(.byteCount(style: .memory, spellsOutZero: false)) } ?? "—"
        return String(localized: "\(cpu), \(memory), \(group.processCount) processus")
    }

    /// « 75 %, 1,4 Mo » — la mémoire des processus arrive en Kio, pas en octets.
    func activityText(for process: SystemProcess) -> String {
        let cpu = process.cpuPercent.map { String(localized: "\($0) %") } ?? "—"
        guard let memoryKiB = process.memoryKiB,
              let bytes = Int64(exactly: memoryKiB)?.multipliedReportingOverflow(by: 1024).partialValue,
              memoryKiB >= 0 else {
            return cpu
        }
        let memory = bytes.formatted(.byteCount(style: .memory, spellsOutZero: false))
        return String(localized: "\(cpu), \(memory)")
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "\(groups.count) services, \(totalProcessCount) processus")
    }
}
