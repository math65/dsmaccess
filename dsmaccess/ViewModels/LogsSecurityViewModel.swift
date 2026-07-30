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
    /// Vrai le temps d'aller chercher les entrées suivantes, pour désarmer le bouton.
    private(set) var isLoadingMore = false
    /// Vrai le temps que le NAS produise le fichier d'export.
    private(set) var isExporting = false
    private(set) var blockedAddresses: [BlockedAddress] = []
    private(set) var loginActivity: [LoginActivityEvent] = []
    var loginActivityError: String?
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

    /// Journal consulté. Le NAS en tient un par protocole en plus du système et des connexions.
    private(set) var kind: SystemLogKind = .system
    /// Journaux proposés : ceux que le NAS tient toujours, plus les protocoles dont la
    /// journalisation des transferts est activée.
    private(set) var availableKinds: [SystemLogKind] = SystemLogKind.always

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

        await loadAvailableKinds(generation: generation)

        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        do {
            let requested = kind
            let page = try await session.withClient {
                try await $0.systemLogs(
                    kind: requested,
                    limit: Self.logPageLimit,
                    offset: 0,
                    keyword: keyword
                )
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
        await loadLoginActivity(generation: generation)

        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: errorMessage == nil ? .result : .error)
        }
    }

    /// L'activité de connexion vient du Conseiller de sécurité, une autre API que les journaux :
    /// elle porte donc son erreur, pour qu'un refus n'emporte pas le reste de l'écran.
    private func loadLoginActivity(generation: Int) async {
        loginActivityError = nil
        do {
            let page = try await session.withClient {
                try await $0.loginActivity(limit: Self.loginActivityLimit)
            }
            guard generation == loadGeneration else { return }
            loginActivity = page.events.sorted { $0.sortableDate > $1.sortableDate }
        } catch {
            guard generation == loadGeneration, !DSMError.isCancellation(error) else { return }
            loginActivity = []
            loginActivityError = (error as? DSMError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    static let loginActivityLimit = 200

    /// Journaux à proposer. Un journal de transfert dont le protocole n'est pas journalisé
    /// renverrait zéro entrée sans erreur, ce qui se lirait comme un journal vide : mieux vaut
    /// ne pas le proposer. L'échec de cette lecture n'est pas une erreur de l'écran — on s'en
    /// tient alors aux journaux que le NAS tient toujours.
    private func loadAvailableKinds(generation: Int) async {
        guard availableKinds == SystemLogKind.always else { return }
        let logging = try? await session.withClient { try await $0.fileTransferLogging() }
        guard generation == loadGeneration, let logging else { return }
        availableKinds = SystemLogKind.always
            + SystemLogKind.transfers.filter(logging.enabled.contains)
    }

    /// Change de journal. Chaque journal a sa propre pagination et son propre décompte : la
    /// liste repart de sa première tranche.
    func select(_ kind: SystemLogKind) async {
        guard kind != self.kind else { return }
        self.kind = kind
        logs = []
        totalLogCount = 0
        await load(announce: true)
    }

    /// Ajoute la tranche suivante du journal à celle déjà affichée, sans rien remplacer : les
    /// entrées déjà lues restent en place et le tableau grandit.
    ///
    /// La pagination du NAS se fait par rang, non par horodatage : si le NAS consigne une
    /// nouvelle entrée entre deux tranches, tout se décale d'un cran et une entrée peut
    /// apparaître deux fois ou passer à la trappe. DSM a la même limite. Renvoie le message à
    /// annoncer, ou `nil` s'il n'y avait rien à charger.
    func loadMore() async -> DSMOperationOutcome? {
        guard canLoadMore, !isLoadingMore else { return nil }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let generation = loadGeneration
        let offset = logs.count
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        do {
            let requested = kind
            let page = try await session.withClient {
                try await $0.systemLogs(
                    kind: requested,
                    limit: Self.logPageLimit,
                    offset: offset,
                    keyword: keyword
                )
            }
            // Un rechargement complet a pu partir entre-temps : sa page fait foi, pas la nôtre.
            guard generation == loadGeneration else { return nil }
            guard !page.entries.isEmpty else {
                // Le NAS n'a plus rien à donner : le total qu'il annonçait était optimiste.
                totalLogCount = logs.count
                return .success(String(localized: "Tout le journal est affiché"))
            }
            logs += page.entries.map { $0.renumbered(from: offset) }
            if let total = page.total { totalLogCount = total }
            return .success(summary)
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec du chargement de la suite : \(reason)"))
        }
    }

    var canLoadMore: Bool { totalLogCount > logs.count }

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

    /// Écrit le journal courant dans un fichier. L'export porte sur le journal entier, pas sur
    /// les tranches chargées : le NAS produit le fichier lui-même.
    func export(as format: SystemLogExportFormat, to destination: URL) async -> DSMOperationOutcome {
        isExporting = true
        defer { isExporting = false }
        let exported = kind
        do {
            try await session.withClient {
                try await $0.exportSystemLog(kind: exported, format: format, to: destination)
            }
            return .success(
                String(localized: "Journal exporté vers \(destination.lastPathComponent)")
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "Échec de l’export : \(reason)"))
        }
    }

    /// Nom de fichier proposé : le journal et la date, pour que deux exports ne se recouvrent
    /// pas dans le dossier de destination.
    func suggestedExportName(for format: SystemLogExportFormat) -> String {
        let day = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "\(kindTitle) \(day).\(format.fileExtension)"
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

    private func matches(_ filter: LevelFilter, _ level: SystemLogEntry.Level?) -> Bool {
        switch (filter, level) {
        case (.all, _): true
        case (.error, .error): true
        case (.warning, .warning): true
        case (.info, .info): true
        default: false
        }
    }

    /// Un journal de transfert n'attribue aucune gravité : le tiret dit l'absence là où
    /// « niveau inconnu » laisserait croire à une valeur que nous n'aurions pas su lire.
    func levelText(_ level: SystemLogEntry.Level?) -> String {
        switch level {
        case .info: String(localized: "Information")
        case .warning: String(localized: "Avertissement")
        case .error: String(localized: "Erreur")
        case .other(let raw): raw.isEmpty ? String(localized: "Niveau inconnu") : raw
        case nil: "—"
        }
    }

    func addressText(for entry: SystemLogEntry) -> String { entry.address ?? "—" }

    /// Opération enregistrée par un journal de transfert. DSM emploie des verbes courts et non
    /// traduits ; les plus courants sont rendus en clair, les autres tels quels.
    func operationText(for entry: SystemLogEntry) -> String {
        switch entry.operation?.lowercased() {
        case "read": String(localized: "Lecture")
        case "write": String(localized: "Écriture")
        case "delete": String(localized: "Suppression")
        case "rename": String(localized: "Renommage")
        case "move": String(localized: "Déplacement")
        case "copy": String(localized: "Copie")
        case "create": String(localized: "Création")
        case "mkdir": String(localized: "Création de dossier")
        case nil: "—"
        default: entry.operation ?? "—"
        }
    }

    /// Taille du fichier. Un dossier n'en a pas, et le NAS y écrit zéro.
    func sizeText(for entry: SystemLogEntry) -> String {
        guard let fileSize = entry.fileSize else {
            return entry.isDirectory ? String(localized: "Dossier") : "—"
        }
        return fileSize.formatted(.byteCount(style: .file))
    }

    /// Vrai quand le journal courant décrit des transferts : ses colonnes ne sont pas les mêmes.
    var showsTransferColumns: Bool { kind.isTransfer }

    /// Nom du journal. Les journaux de transfert portent le nom de leur protocole, tel que
    /// Synology l'écrit : ces noms ne se traduisent pas.
    func kindText(_ kind: SystemLogKind) -> String {
        switch kind {
        case .system: String(localized: "Journal système")
        case .connection: String(localized: "Journal de connexion")
        case .afp: "AFP"
        case .cifs: "SMB"
        case .fileStation: "File Station"
        case .ftp: "FTP"
        case .tftp: "TFTP"
        case .webdav: "WebDAV"
        }
    }

    /// Titre de l'écran pour le journal courant, et intitulé annoncé après un changement.
    var kindTitle: String {
        switch kind {
        case .system, .connection: kindText(kind)
        default: String(localized: "Transferts \(kindText(kind))")
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

    // MARK: - Activité de connexion

    /// L'alerte en une phrase. Le NAS n'en fournit aucune : il envoie une clé de son catalogue
    /// et des arguments, que son client web assemble. Chaque clé connue a donc sa phrase
    /// complète, et le compte comme l'adresse restent dans leurs colonnes plutôt que d'être
    /// répétés ici.
    func description(of event: LoginActivityEvent) -> String {
        switch event.kind {
        case .abnormalLogin:
            if let city = event.details.city, let country = countryName(event.details.countryCode) {
                return String(localized: "Connexion inhabituelle depuis \(city), \(country)")
            }
            if let country = countryName(event.details.countryCode) {
                return String(localized: "Connexion inhabituelle depuis \(country)")
            }
            return String(localized: "Connexion inhabituelle")
        case .bruteForceAttack:
            if let attempts = event.details.attemptCount,
               let minutes = event.details.thresholdMinutes {
                return String(
                    localized: "\(attempts) tentatives de connexion échouées en \(minutes) minutes"
                )
            }
            return String(localized: "Tentatives de connexion répétées")
        case .unknown(let section, let identifier):
            // Le NAS a signalé quelque chose que nous ne savons pas formuler : le dire, plutôt
            // que d'inventer une phrase ou de masquer l'alerte.
            let key = identifier.isEmpty ? section : "\(section):\(identifier)"
            return String(localized: "Alerte de sécurité non reconnue (\(key))")
        }
    }

    func severityText(_ severity: LoginActivityEvent.Severity) -> String {
        switch severity {
        case .low: String(localized: "Faible")
        case .medium: String(localized: "Moyenne")
        case .high: String(localized: "Élevée")
        case .other(let raw): raw.isEmpty ? String(localized: "Gravité inconnue") : raw
        }
    }

    func accountText(for event: LoginActivityEvent) -> String {
        event.account ?? event.details.user ?? "—"
    }

    /// Les adresses d'une alerte. Une attaque par force brute peut en porter plusieurs.
    func addressText(for event: LoginActivityEvent) -> String {
        let addresses = event.details.allAddresses
        guard !addresses.isEmpty else { return "—" }
        return addresses.formatted(.list(type: .and))
    }

    func dateText(for event: LoginActivityEvent) -> String {
        guard let recordedAt = event.recordedAt else { return "—" }
        return recordedAt.formatted(date: .abbreviated, time: .standard)
    }

    /// Le NAS envoie un code de pays à deux lettres ; le Mac sait le nommer dans la langue de
    /// l'utilisateur.
    private func countryName(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    var loginActivitySummary: String {
        if let loginActivityError { return loginActivityError }
        let high = loginActivity.filter { $0.severity == .high }.count
        return String(
            localized: "\(loginActivity.count) alertes de connexion, dont \(high) de gravité élevée"
        )
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
        // Un journal de transfert n'a pas de gravité : annoncer « 0 erreur » y serait trompeur.
        if showsTransferColumns {
            if isTruncated {
                return String(
                    localized: "\(visibleLogs.count) entrées affichées sur \(totalLogCount)"
                )
            }
            return String(localized: "\(visibleLogs.count) entrées de journal")
        }
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
