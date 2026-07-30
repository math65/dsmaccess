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
            // Tri par mémoire et non par processeur : la charge d'un service au repos varie
            // d'un centième de point à chaque relevé, et un tri sur ces écarts réordonne la
            // liste à chaque actualisation, ce qui rend le parcours au lecteur d'écran
            // impraticable. La mémoire, elle, bouge lentement. Le tri visible reste celui
            // que l'utilisateur choisit sur les en-têtes du tableau.
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
            String(localized: "common.status.automatic_refresh_on"),
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
                String(localized: "common.status.automatic_refresh_off"),
                category: .automaticRefresh
            )
        }
    }

    func stop() { stopAutoRefresh(announce: false) }

    // MARK: - Affichage formaté

    /// Une mesure absente s'écrit « — » : DSM renvoie littéralement « - » pour les groupes
    /// qu'il ne mesure pas, et écrire zéro à la place ferait passer une absence de mesure
    /// pour un service au repos.
    func cpuText(for group: ProcessGroup) -> String {
        guard let cpu = group.cpuPercent else { return "—" }
        return String(localized: "tasks.percent.value", defaultValue: "\(cpu.formatted(.number.precision(.fractionLength(1))))%")
    }

    func memoryText(for group: ProcessGroup) -> String {
        guard let bytes = group.memoryBytes else { return "—" }
        return bytes.formatted(.byteCount(style: .memory, spellsOutZero: false))
    }

    // MARK: - Mesures que DSM n'affiche pas

    /// Temps processeur cumulé depuis le démarrage du service.
    func cpuTimeText(for group: ProcessGroup) -> String {
        guard let seconds = group.cpuTime, seconds >= 0 else { return "—" }
        return Duration.seconds(seconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .narrow)
        )
    }

    func readRateText(for group: ProcessGroup) -> String {
        rateText(group.readBytesPerSecond)
    }

    func writeRateText(for group: ProcessGroup) -> String {
        rateText(group.writeBytesPerSecond)
    }

    /// Un tiret quand DSM n'a pas mesuré, un débit sinon — y compris zéro, qui est ici une
    /// mesure et non une absence : un service au repos n'écrit réellement rien.
    private func rateText(_ bytesPerSecond: Int64?) -> String {
        guard let bytesPerSecond, bytesPerSecond >= 0 else { return "—" }
        let formatted = bytesPerSecond.formatted(.byteCount(style: .memory, spellsOutZero: false))
        return String(localized: "common.unit.per_second", defaultValue: "\(formatted)/s")
    }

    func cpuText(for process: SystemProcess) -> String {
        guard let cpu = process.cpuPercent else { return "—" }
        return String(localized: "common.unit.percent", defaultValue: "\(cpu)%")
    }

    /// La mémoire des processus arrive en Kio, pas en octets comme celle des groupes.
    func memoryText(for process: SystemProcess) -> String {
        guard let memoryKiB = process.memoryKiB, memoryKiB >= 0,
              let kib = Int64(exactly: memoryKiB) else { return "—" }
        let (bytes, overflow) = kib.multipliedReportingOverflow(by: 1024)
        guard !overflow else { return "—" }
        return bytes.formatted(.byteCount(style: .memory, spellsOutZero: false))
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "tasks.count.summary", defaultValue: "\(groups.count) services, \(totalProcessCount) processes")
    }
}
