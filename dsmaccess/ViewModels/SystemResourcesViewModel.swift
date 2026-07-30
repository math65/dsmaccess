//
//  SystemResourcesViewModel.swift
//  dsmaccess
//
//  Charge et expose les mesures instantanées du NAS (processeur, mémoire, réseau).
//  Gère une actualisation automatique optionnelle (boucle 5 s), pensée pour VoiceOver :
//  les mises à jour périodiques sont SILENCIEUSES (pas de spam d'annonces) ; seule une
//  actualisation manuelle réannonce le résumé.
//

import Foundation
import Observation

@MainActor
@Observable
final class SystemResourcesViewModel {
    private(set) var usage: ResourceUsage?
    private(set) var isLoading = false
    var errorMessage: String?

    /// Actualisation périodique. Piloté par le Toggle de la vue ; démarre/arrête la boucle.
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

    /// Recharge les mesures. `announce == true` réannonce le résumé (actualisation manuelle).
    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if usage == nil { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { try await $0.resourceUsage() }
            guard generation == loadGeneration else { return }
            usage = result
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    // MARK: - Actualisation automatique

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
                await self?.load()   // silencieux : pas d'annonce à chaque tick
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

    /// Coupe la boucle sans annonce (appelé quand l'écran disparaît).
    func stop() {
        stopAutoRefresh(announce: false)
    }

    // MARK: - Affichage formaté

    /// Charge processeur totale en pourcentage (utilisateur + système + autre).
    var cpuPercent: Int? {
        guard let cpu = usage?.cpu else { return nil }
        let values = [cpu.userLoad, cpu.systemLoad, cpu.otherLoad]
            .compactMap { $0 }
            .filter { (0...100).contains($0) }
        return values.isEmpty ? nil : min(values.reduce(0, +), 100)
    }

    var cpuText: String {
        cpuPercent.map { String(localized: "\($0) %") } ?? "—"
    }

    /// Répartition entre temps utilisateur et temps système. DSM met parfois toute la charge
    /// dans `other_load` et renvoie zéro pour les deux autres — relevé sur un DS920+ à 27 %
    /// de charge, puis « utilisateur 6 %, système 31 % » quelques minutes plus tard sur la
    /// même machine. C'est donc un état passager, pas une propriété du modèle. Quand les deux
    /// valeurs sont nulles, la ligne disparaît : « Utilisateur 0 %, système 0 % » sous une
    /// charge non nulle se lit comme une mesure cassée et contredit la ligne du dessus.
    var cpuDetailText: String? {
        guard let cpu = usage?.cpu, let user = cpu.userLoad, let system = cpu.systemLoad else { return nil }
        guard user > 0 || system > 0 else { return nil }
        return String(localized: "Utilisateur \(user) %, système \(system) %")
    }

    var memoryPercent: Int? {
        usage?.memory?.realUsage.flatMap { (0...100).contains($0) ? $0 : nil }
    }

    var memoryText: String {
        memoryPercent.map { String(localized: "\($0) %") } ?? "—"
    }

    /// « 0,64 Go sur 3,68 Go » (les tailles DSM sont en Kio → conversion en octets). Le
    /// volume affiché exclut le cache, comme le pourcentage juste au-dessus : les deux
    /// lignes doivent raconter la même chose.
    var memoryDetailText: String? {
        guard let mem = usage?.memory,
              let total = mem.totalReal,
              total >= 0,
              let totalKiB = Int64(exactly: total),
              let used = mem.usedReal,
              (0...total).contains(used),
              let usedKiB = Int64(exactly: used) else { return nil }
        let (usedBytes, usedOverflow) = usedKiB.multipliedReportingOverflow(by: 1024)
        let (totalBytes, totalOverflow) = totalKiB.multipliedReportingOverflow(by: 1024)
        guard !usedOverflow, !totalOverflow else { return nil }
        return String(localized: "\(usedBytes.formatted(.byteCount(style: .memory))) sur \(totalBytes.formatted(.byteCount(style: .memory)))")
    }

    var swapText: String? {
        guard let swap = usage?.memory?.swapUsage, (0...100).contains(swap) else { return nil }
        return String(localized: "\(swap) %")
    }

    /// Interface synthétique « total » (repli sur la première si absente).
    private var totalInterface: ResourceUsage.Interface? {
        usage?.network?.first { $0.device == "total" } ?? usage?.network?.first
    }

    var networkDownText: String { rateText(totalInterface?.rx) }
    var networkUpText: String { rateText(totalInterface?.tx) }

    /// `spellsOutZero` désactivé : le style par défaut écrit « Zéro ko », ce qui se lit mal
    /// dans une ligne de mesures et s'entend encore plus mal.
    private func rateText(_ bytesPerSecond: Int?) -> String {
        guard let bytesPerSecond, bytesPerSecond >= 0 else { return "—" }
        let formatted = Int64(bytesPerSecond)
            .formatted(.byteCount(style: .memory, spellsOutZero: false))
        return String(localized: "\(formatted)/s")
    }

    /// Moyennes de charge sur une, cinq et quinze minutes. Absentes tant que DSM n'en
    /// renvoie aucune plutôt qu'affichées à zéro, qui se lirait comme une mesure.
    var loadAverageText: String? {
        guard let cpu = usage?.cpu,
              let one = cpu.oneMinuteLoad,
              let five = cpu.fiveMinuteLoad,
              let fifteen = cpu.fifteenMinuteLoad else { return nil }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
        return String(
            localized: "\(one.formatted(format)) sur 1 minute, \(five.formatted(format)) sur 5 minutes, \(fifteen.formatted(format)) sur 15 minutes"
        )
    }

    /// Disques physiques, hors entrée cumulée que DSM range à part. Triés par nom : le NAS
    /// les renvoie dans un ordre qui lui est propre (Drive 4, 3, 1, 2), déroutant à lire
    /// comme à parcourir au clavier.
    var disks: [ResourceUsage.Device] {
        (usage?.disk?.devices ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    var diskTotal: ResourceUsage.Device? { usage?.disk?.total }
    var volumes: [ResourceUsage.Device] { usage?.space?.devices ?? [] }

    /// « 14 %, 859 Ko/s en lecture, 16 Ko/s en écriture ». Le taux d'utilisation seul ne
    /// dit pas si le disque peine sur des lectures ou des écritures.
    func activityText(for device: ResourceUsage.Device) -> String {
        let read = rateText(device.readBytesPerSecond)
        let write = rateText(device.writeBytesPerSecond)
        guard let utilization = device.utilization, (0...100).contains(utilization) else {
            return String(localized: "\(read) en lecture, \(write) en écriture")
        }
        return String(localized: "\(utilization) %, \(read) en lecture, \(write) en écriture")
    }

    /// Résumé annoncé à VoiceOver après une actualisation manuelle.
    var summary: String {
        if let errorMessage { return errorMessage }
        let cpu = cpuPercent.map(String.init) ?? "—"
        let mem = memoryPercent.map(String.init) ?? "—"
        return String(localized: "Processeur \(cpu) %, mémoire \(mem) %")
    }
}
