//
//  FeedbackDiagnostics.swift
//  dsmaccess
//
//  Instantané de diagnostic joint aux signalements de problème. Les libellés sont
//  en français littéral (et non localisés) : ils composent l'e-mail reçu par le
//  développeur, pas l'interface. Aucune donnée du NAS n'y figure : ni adresse,
//  ni compte, ni nom de profil, ni identifiant de session.
//

import AppKit

enum FeedbackDiagnostics {
    static func sections(
        sessionConnected: Bool,
        profileCount: Int,
        settings: AppSettings,
        incident: DSMResponseIncident? = nil
    ) -> [AppBackendClient.ReportSection] {
        let bundle = Bundle.main
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "inconnu"
        let language = bundle.preferredLocalizations.first ?? "inconnue"

        let hiddenModules = AppModule.allCases.filter { !settings.enabledSidebarModules.contains($0) }
        let announcementCategories = AnnouncementCategory.allCases
            .filter { settings.enabledAnnouncementCategories.contains($0) }

        var sections = [
            AppBackendClient.ReportSection(title: "Application", rows: [
                .init(label: "Version", value: AppBackendClient.appVersion),
                .init(label: "Build", value: build),
                .init(label: "Langue", value: language),
                .init(label: "VoiceOver actif", value: NSWorkspace.shared.isVoiceOverEnabled ? "oui" : "non"),
            ]),
            AppBackendClient.ReportSection(title: "Système", rows: [
                .init(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString),
            ]),
            AppBackendClient.ReportSection(title: "NAS", rows: [
                .init(label: "Session connectée", value: sessionConnected ? "oui" : "non"),
                .init(label: "Profils enregistrés", value: String(profileCount)),
            ]),
            AppBackendClient.ReportSection(title: "Réglages", rows: [
                .init(label: "Catégories d'annonces actives", value: announcementCategories.isEmpty
                    ? "aucune"
                    : announcementCategories.map(\.rawValue).joined(separator: ", ")),
                .init(label: "Regroupement des annonces", value: settings.queueAnnouncements ? "oui" : "non"),
                .init(label: "Modules masqués", value: hiddenModules.isEmpty
                    ? "aucun"
                    : hiddenModules.map(\.rawValue).joined(separator: ", ")),
            ]),
        ]

        if let incident {
            sections.append(
                AppBackendClient.ReportSection(title: "Réponse illisible", rows: [
                    .init(label: "API", value: incident.api),
                    .init(label: "Méthode", value: incident.method),
                    .init(label: "Version", value: incident.version),
                    .init(label: "Échec", value: incident.failure),
                ] + incident.receivedFields.enumerated().map { index, fields in
                    .init(label: "Champs reçus \(index + 1)", value: fields)
                })
            )
        }
        return sections
    }
}
