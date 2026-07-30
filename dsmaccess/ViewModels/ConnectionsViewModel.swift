//
//  ConnectionsViewModel.swift
//  dsmaccess
//
//  Onglet Connexions du moniteur de ressources : qui est connecté au NAS, depuis où et
//  par quel protocole, et la coupure des sessions ouvertes.
//

import Foundation
import Observation

@MainActor
@Observable
final class ConnectionsViewModel {
    private(set) var connections: [NASConnection] = []
    private(set) var isLoading = false
    var errorMessage: String?
    /// Sessions dont la coupure est en cours, pour désarmer le bouton le temps de l'appel.
    private(set) var busyIDs: Set<String> = []

    private let session: SessionStore
    private var loadGeneration = 0

    init(session: SessionStore) {
        self.session = session
    }

    func load(announce: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if connections.isEmpty { isLoading = true }
        errorMessage = nil
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await session.withClient { try await $0.connections() }
            guard generation == loadGeneration else { return }
            // Le tri visible appartient au tableau ; ici, seul un ordre de départ stable
            // est fixé, de la session la plus récente à la plus ancienne.
            connections = result.sorted {
                ($0.openedAt ?? .distantPast) > ($1.openedAt ?? .distantPast)
            }
        } catch {
            if generation == loadGeneration, !DSMError.isCancellation(error) {
                errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            }
        }
        if announce, generation == loadGeneration {
            VoiceOver.announce(summary, category: .result, priority: .low)
        }
    }

    /// Coupe les sessions indiquées en un seul appel, comme le fait DSM. Les entrées que le
    /// NAS déclare non coupables sont écartées ici : les envoyer ferait échouer tout le lot.
    func kick(_ selection: [NASConnection]) async -> DSMOperationOutcome {
        let kickable = selection.filter { $0.kickReference != nil }
        guard !kickable.isEmpty else {
            return .failure(String(localized: "connections.disconnect.unsupported_selection"))
        }

        busyIDs.formUnion(kickable.map(\.id))
        defer { busyIDs.subtract(kickable.map(\.id)) }

        do {
            let references = kickable.compactMap(\.kickReference)
            try await session.withClient { try await $0.kickConnections(references) }
            // La liste est rechargée plutôt que corrigée sur place : couper une session web
            // en ferme parfois d'autres du même appareil, et le NAS seul sait lesquelles.
            await load()
            if let only = kickable.first, kickable.count == 1 {
                return .success(
                    String(localized: "connections.disconnect.success", defaultValue: "\(accountText(for: only))’s session disconnected")
                )
            }
            return .success(String(localized: "connections.disconnect.success_multiple", defaultValue: "\(kickable.count) sessions disconnected"))
        } catch {
            guard !DSMError.isCancellation(error) else { return .cancelled }
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            return .failure(String(localized: "connections.disconnect.error", defaultValue: "Could not disconnect: \(reason)"))
        }
    }

    /// Vrai quand la sélection contient une session web du compte avec lequel l'app est
    /// connectée. `is_current_connected` ne sert à rien ici : vérifié sur DSM 7.4, le NAS ne
    /// le lève que pour son propre client web. La comparaison du compte reste donc le seul
    /// signal disponible, et elle peut désigner une autre session que celle de l'app.
    func mayCloseOwnSession(_ selection: [NASConnection]) -> Bool {
        guard let account = session.activeProfile?.account else { return false }
        return selection.contains {
            $0.isWebSession
                && $0.account?.caseInsensitiveCompare(account) == .orderedSame
        }
    }

    func canKick(_ connection: NASConnection) -> Bool {
        connection.kickReference != nil && !busyIDs.contains(connection.id)
    }

    func accountText(for connection: NASConnection) -> String {
        connection.account ?? String(localized: "connections.account.unknown")
    }

    // MARK: - Valeurs que DSM n'affiche pas
    //
    // Le NAS les renvoie depuis toujours. Un tiret quand elles sont vides, comme partout
    // ailleurs dans ce module : le NAS ne renseigne le client et le lieu que pour certaines
    // sessions, et un accès local n'en produit aucun.

    func clientText(for connection: NASConnection) -> String {
        connection.userAgent ?? "—"
    }

    func locationText(for connection: NASConnection) -> String {
        connection.location ?? "—"
    }

    /// Savoir qu'une session s'est ouverte *sans* second facteur est au moins aussi utile que
    /// l'inverse : la colonne dit toujours quelque chose. L'appareil de confiance est précisé
    /// dans la même colonne, faute de mériter la sienne.
    func twoFactorText(for connection: NASConnection) -> String {
        switch (connection.usesTwoFactor, connection.isTrustedDevice) {
        case (true, true): String(localized: "connections.trusted_device.yes")
        case (true, false): String(localized: "common.answer.yes")
        case (false, true): String(localized: "connections.trusted_device.no")
        case (false, false): String(localized: "common.answer.no")
        }
    }

    /// Horodatage rendu dans la langue du Mac. Un tiret quand DSM a envoyé une forme que
    /// nous n'avons pas su lire : la connexion reste listée, sans date inventée.
    func openedAtText(for connection: NASConnection) -> String {
        guard let openedAt = connection.openedAt else { return "—" }
        return openedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var summary: String {
        if let errorMessage { return errorMessage }
        return String(localized: "connections.summary.open_count", defaultValue: "\(connections.count) open connections")
    }
}
