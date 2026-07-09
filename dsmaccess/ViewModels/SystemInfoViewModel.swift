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
            info = try await client.systemInfo(sid: sid)
        } catch {
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Affichage formaté

    var ramText: String {
        guard let ram = info?.ram else { return "—" }
        return String(localized: "\(ram) Mo")
    }

    var uptimeText: String {
        guard let uptime = info?.uptime else { return "—" }
        let days = uptime / 86_400
        let hours = (uptime % 86_400) / 3_600
        let minutes = (uptime % 3_600) / 60
        if days > 0 {
            return String(localized: "\(days) j \(hours) h \(minutes) min")
        } else if hours > 0 {
            return String(localized: "\(hours) h \(minutes) min")
        } else {
            return String(localized: "\(minutes) min")
        }
    }

    var temperatureText: String {
        guard let temp = info?.temperature else { return "—" }
        let base = String(localized: "\(temp) °C")
        let warn = info?.temperatureWarn == true ? String(localized: " (alerte)") : ""
        return base + warn
    }
}
