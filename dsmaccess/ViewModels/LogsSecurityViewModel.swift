//
//  LogsSecurityViewModel.swift
//  dsmaccess
//
//  Journal système du NAS et liste de blocage du blocage automatique.
//
//  Les deux lectures sont indépendantes : un NAS dont la liste de blocage est refusée doit
//  quand même montrer son journal, et l'inverse. Chacune porte donc son erreur.
//

import Foundation
import Observation

@MainActor
@Observable
final class LogsSecurityViewModel {
    /// Un NAS actif accumule des milliers d'entrées — 6995 sur le DS920+ de développement. La
    /// page est large mais bornée, et l'écran dit ce qu'il ne montre pas.
    static let logPageLimit = 1000
    static let blockedPageLimit = 500

    private(set) var logs: [SystemLogEntry] = []
    /// Nombre d'entrées conservées par le NAS, qui dépasse souvent la page chargée.
    private(set) var totalLogCount = 0
    private(set) var blockedAddresses: [BlockedAddress] = []
    private(set) var isLoading = false
    /// Adresses dont le déblocage est en cours, pour désarmer leurs commandes.
    private(set) var busyAddresses: Set<String> = []
    var errorMessage: String?
    var blockedAddressesError: String?

    /// Recherche transmise au NAS, qui filtre lui-même le journal.
    var searchText = "" {
        didSet { if searchText != oldValue { scheduleSearch() } }
    }
    /// Gravité retenue. Le filtrage est local : vérifié sur DSM 7.4, le NAS accepte un
    /// paramètre `level` puis l'ignore.
    var levelFilter: LevelFilter = .all

    enum LevelFilter: Hashable, CaseIterable, Identifiable {
        case all
        case error
        case warning
        case info

        var id: Self { self }
    }

    private let session: SessionStore
    private var loadGeneration = 0
    /// Une frappe ne doit pas déclencher une requête par caractère.
    private var searchTask: Task<Void, Never>?

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if logs.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }

        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        do {
            let page = try await session.withClient {
                try await $0.systemLogs(limit: Self.logPageLimit, keyword: keyword)
            }
            guard generation == loadGeneration else { return }
            logs = page.entries
            totalLogCount = page.total ?? page.entries.count
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }

        await loadBlockedAddresses(generation: generation)

        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: errorMessage == nil ? .result : .error)
        }
    }

    /// La liste de blocage a sa propre erreur : le journal reste consultable même si le NAS la
    /// refuse, ce qui est le cas d'un compte sans privilège d'administration.
    private func loadBlockedAddresses(generation: Int) async {
        blockedAddressesError = nil
        do {
            let page = try await session.withClient {
                try await $0.blockedAddresses(limit: Self.blockedPageLimit)
            }
            guard generation == loadGeneration else { return }
            blockedAddresses = page.addresses.sorted {
                $0.sortableBlockedAt > $1.sortableBlockedAt
            }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            blockedAddresses = []
            blockedAddressesError = (error as? DSMError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    /// Le NAS filtre le journal lui-même : la recherche est renvoyée chez lui, après une courte
    /// pause pour ne pas interroger le NAS à chaque frappe.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func unblock(_ addresses: [BlockedAddress]) async -> DSMOperationOutcome {
        guard !addresses.isEmpty else { return .cancelled }
        let values = addresses.map(\.address)
        busyAddresses.formUnion(values)
        defer { busyAddresses.subtract(values) }
        do {
            try await session.withClient { try await $0.unblockAddresses(values) }
            // La liste est rechargée plutôt que corrigée sur place : le blocage automatique
            // peut avoir ajouté ou fait expirer des adresses entre-temps.
            await loadBlockedAddresses(generation: loadGeneration)
            if values.count == 1, let only = values.first {
                return .success(String(localized: "Adresse débloquée : \(only)"))
            }
            return .success(String(localized: "\(values.count) adresses débloquées"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec du déblocage : \(reason)"))
        }
    }

    // MARK: - Présentation

    /// Entrées effectivement affichées. Seule la gravité est filtrée ici : le mot-clé a déjà
    /// été appliqué par le NAS.
    var visibleLogs: [SystemLogEntry] {
        guard levelFilter != .all else { return logs }
        return logs.filter { matches(levelFilter, $0.level) }
    }

    private func matches(_ filter: LevelFilter, _ level: SystemLogEntry.Level) -> Bool {
        switch (filter, level) {
        case (.all, _): true
        case (.error, .error): true
        case (.warning, .warning): true
        case (.info, .info): true
        default: false
        }
    }

    func levelText(_ level: SystemLogEntry.Level) -> String {
        switch level {
        case .info: String(localized: "Information")
        case .warning: String(localized: "Avertissement")
        case .error: String(localized: "Erreur")
        case .other(let raw): raw.isEmpty ? String(localized: "Niveau inconnu") : raw
        }
    }

    func filterText(_ filter: LevelFilter) -> String {
        switch filter {
        case .all: String(localized: "Tous les niveaux")
        case .error: String(localized: "Erreurs")
        case .warning: String(localized: "Avertissements")
        case .info: String(localized: "Informations")
        }
    }

    /// Catégorie de l'entrée. La valeur technique est traduite par l'app, pour qu'elle suive la
    /// langue de l'app et non celle du compte DSM ; la traduction du NAS ne sert que de repli
    /// pour une catégorie que nous ne connaissons pas.
    func categoryText(for entry: SystemLogEntry) -> String {
        switch entry.technicalCategory?.lowercased() {
        case "system": String(localized: "Système")
        case "connection": String(localized: "Connexion")
        case "filetransfer": String(localized: "Transfert de fichiers")
        default: entry.translatedCategory ?? "—"
        }
    }

    func accountText(for entry: SystemLogEntry) -> String { entry.account ?? "—" }

    /// Horodatage rendu dans la langue du Mac. Un tiret quand DSM a envoyé une forme que nous
    /// n'avons pas su lire : l'entrée reste listée, sans date inventée.
    func dateText(for entry: SystemLogEntry) -> String {
        guard let recordedAt = entry.recordedAt else { return "—" }
        return recordedAt.formatted(date: .abbreviated, time: .standard)
    }

    func blockedAtText(for address: BlockedAddress) -> String {
        guard let blockedAt = address.blockedAt else { return "—" }
        return blockedAt.formatted(date: .abbreviated, time: .standard)
    }

    /// Un blocage sans expiration est la valeur par défaut de DSM. Le NAS envoie alors zéro,
    /// qu'il formate lui-même en 1970 — d'où une date jamais reprise telle quelle.
    func expiryText(for address: BlockedAddress) -> String {
        guard let expiresAt = address.expiresAt else {
            return String(localized: "Définitivement")
        }
        return expiresAt.formatted(date: .abbreviated, time: .shortened)
    }

    func countryText(for address: BlockedAddress) -> String {
        guard let country = address.country, !country.isEmpty else {
            return String(localized: "Lieu inconnu")
        }
        return Locale.current.localizedString(forRegionCode: country) ?? country
    }

    func canUnblock(_ address: BlockedAddress) -> Bool {
        !busyAddresses.contains(address.address)
    }

    /// Vrai quand le NAS en conserve plus que ce qui a été chargé.
    var isTruncated: Bool { totalLogCount > logs.count }

    /// Décompte des gravités présentes dans la page chargée. Recalculé sur place plutôt que lu
    /// dans la réponse : le NAS renvoie bien `errorCount` et ses voisins, mais ils portent sur
    /// la page entière, alors que l'écran peut en filtrer une partie.
    var visibleErrorCount: Int { visibleLogs.filter { $0.level == .error }.count }
    var visibleWarningCount: Int { visibleLogs.filter { $0.level == .warning }.count }

    var summary: String {
        if let errorMessage { return errorMessage }
        let errors = visibleErrorCount
        let warnings = visibleWarningCount
        if isTruncated {
            return String(
                localized: "\(visibleLogs.count) entrées affichées sur \(totalLogCount), dont \(errors) erreurs et \(warnings) avertissements"
            )
        }
        return String(
            localized: "\(visibleLogs.count) entrées de journal, dont \(errors) erreurs et \(warnings) avertissements"
        )
    }
}
