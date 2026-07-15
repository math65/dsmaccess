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

    init(session: SessionStore) {
        self.session = session
    }

    /// Recharge les mesures. `announce == true` réannonce le résumé (actualisation manuelle).
    func load(announce: Bool = false) async {
        if usage == nil { isLoading = true }
        errorMessage = nil
        do {
            usage = try await session.withClient { try await $0.resourceUsage() }
        } catch {
            if !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
        if announce {
            VoiceOver.announce(summary, priority: .low)
        }
    }

    // MARK: - Actualisation automatique

    private func startAutoRefresh() {
        VoiceOver.announce(String(localized: "Actualisation automatique activée"))
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
            VoiceOver.announce(String(localized: "Actualisation automatique désactivée"))
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
        let values = [cpu.userLoad, cpu.systemLoad, cpu.otherLoad].compactMap { $0 }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var cpuText: String {
        cpuPercent.map { String(localized: "\($0) %") } ?? "—"
    }

    var cpuDetailText: String? {
        guard let cpu = usage?.cpu, let user = cpu.userLoad, let system = cpu.systemLoad else { return nil }
        return String(localized: "Utilisateur \(user) %, système \(system) %")
    }

    var memoryPercent: Int? { usage?.memory?.realUsage }

    var memoryText: String {
        memoryPercent.map { String(localized: "\($0) %") } ?? "—"
    }

    /// « 3,2 Go sur 8 Go » (les tailles DSM sont en Kio → conversion en octets).
    var memoryDetailText: String? {
        guard let mem = usage?.memory, let total = mem.totalReal else { return nil }
        let used = max(0, total - (mem.availReal ?? 0))
        let usedBytes = Int64(used) * 1024
        let totalBytes = Int64(total) * 1024
        return String(localized: "\(usedBytes.formatted(.byteCount(style: .memory))) sur \(totalBytes.formatted(.byteCount(style: .memory)))")
    }

    var swapText: String? {
        guard let swap = usage?.memory?.swapUsage else { return nil }
        return String(localized: "\(swap) %")
    }

    /// Interface synthétique « total » (repli sur la première si absente).
    private var totalInterface: ResourceUsage.Interface? {
        usage?.network?.first { $0.device == "total" } ?? usage?.network?.first
    }

    var networkDownText: String { rateText(totalInterface?.rx) }
    var networkUpText: String { rateText(totalInterface?.tx) }

    private func rateText(_ bytesPerSecond: Int?) -> String {
        guard let bytesPerSecond else { return "—" }
        let formatted = Int64(bytesPerSecond).formatted(.byteCount(style: .memory))
        return String(localized: "\(formatted)/s")
    }

    /// Résumé annoncé à VoiceOver après une actualisation manuelle.
    var summary: String {
        if let errorMessage { return errorMessage }
        let cpu = cpuPercent.map(String.init) ?? "—"
        let mem = memoryPercent.map(String.init) ?? "—"
        return String(localized: "Processeur \(cpu) %, mémoire \(mem) %")
    }
}
