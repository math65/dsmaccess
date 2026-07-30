//
//  SystemInfoViewModel.swift
//  dsmaccess
//
//  Charge et expose les infos système du NAS ; gère la déconnexion.
//

import Foundation
import Observation

@MainActor
@Observable
final class SystemInfoViewModel {
    private(set) var info: SystemInfo?
    private(set) var isLoading = false
    var errorMessage: String?

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { try await $0.systemInfo() }
            guard generation == loadGeneration else { return }
            info = result
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Affichage formaté

    var ramText: String {
        guard let ram = info?.ram else { return "—" }
        return String(localized: "system_info.memory.megabytes", defaultValue: "\(ram) MB")
    }

    var uptimeText: String {
        guard let uptime = info?.uptime else { return "—" }
        let days = uptime / 86_400
        let hours = (uptime % 86_400) / 3_600
        let minutes = (uptime % 3_600) / 60
        if days > 0 {
            return String(localized: "system_info.uptime.days_hours_minutes", defaultValue: "\(days) d \(hours) h \(minutes) min")
        } else if hours > 0 {
            return String(localized: "system_info.uptime.hours_minutes", defaultValue: "\(hours) h \(minutes) min")
        } else {
            return String(localized: "system_info.uptime.minutes", defaultValue: "\(minutes) min")
        }
    }

    var temperatureText: String {
        guard let temp = info?.temperature else { return "—" }
        let base = String(localized: "common.unit.celsius", defaultValue: "\(temp) °C")
        let warn = info?.temperatureWarn == true ? String(localized: "system_info.status.alert_suffix") : ""
        return base + warn
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        guard let info else { return String(localized: "system_info.unavailable.error") }
        return String(localized: "system_info.model_and_dsm.summary", defaultValue: "\(info.model), DSM \(info.versionString)")
    }
}
