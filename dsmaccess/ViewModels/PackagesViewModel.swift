//
//  PackagesViewModel.swift
//  dsmaccess
//
//  Charge la liste des paquets installés (SYNO.Core.Package) et croise leur version avec
//  le catalogue (SYNO.Core.Package.Server) pour signaler les mises à jour disponibles.
//  Lecture seule : on détecte les mises à jour, on ne les applique pas.
//

import Foundation
import Observation

@MainActor
@Observable
final class PackagesViewModel {
    private(set) var packages: [PackageInfo] = []
    /// Versions disponibles au catalogue, par identifiant minuscule.
    private(set) var availableVersions: [String: String] = [:]
    private(set) var isLoading = false
    var errorMessage: String?
    /// Paquets dont une bascule démarrer/arrêter est en cours (bouton désactivé le temps de l'appel).
    private(set) var busy: Set<String> = []

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
            packages = try await client.listPackages(sid: sid).sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            // Catalogue (pour détecter les mises à jour) ; sans bloquer si indisponible.
            availableVersions = (try? await client.availablePackageVersions(sid: sid)) ?? [:]
        } catch {
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Démarre ou arrête un paquet. Renvoie le message à annoncer à VoiceOver.
    func setRunning(_ package: PackageInfo, running: Bool) async -> String {
        guard let client = session.client, let sid = session.sid else {
            return String(localized: "Session expirée.")
        }
        guard let id = package.pkgId else {
            return String(localized: "Identifiant de paquet introuvable.")
        }
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await client.setPackageRunning(id: id, running: running, sid: sid)
            await load()   // relit l'état réel du paquet
            return running
                ? String(localized: "\(package.displayName) démarré")
                : String(localized: "\(package.displayName) arrêté")
        } catch {
            let reason = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            await load()
            return String(localized: "Échec pour \(package.displayName) : \(reason)")
        }
    }

    /// Version disponible au catalogue si elle est *strictement plus récente* que
    /// l'installée (= vraie mise à jour), sinon nil. On compare l'ordre des versions et
    /// non une simple différence : un paquet système (ex. FileStation, livré avec DSM) ou
    /// à canal propre (ex. Plex) peut être installé dans une version plus récente que celle
    /// du catalogue — ce n'est pas une mise à jour, il ne faut pas proposer de downgrade.
    func updateVersion(for package: PackageInfo) -> String? {
        guard let id = package.pkgId?.lowercased(),
              let available = availableVersions[id],
              let installed = package.version,
              Self.isVersion(available, newerThan: installed) else { return nil }
        return available
    }

    /// Compare deux versions Synology (format "X.Y.Z-BUILD", ex. "1.4.4-2221" ou
    /// "1.43.2.10687-720010687") : true si `candidate` est strictement plus récente que
    /// `current`. Découpe sur "." et "-", compare chaque segment numériquement (un segment
    /// manquant vaut 0). Les versions Synology sont toujours numériques.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = versionComponents(candidate)
        let b = versionComponents(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
    }

    /// Nombre de paquets ayant une mise à jour disponible.
    var updateCount: Int {
        packages.filter { updateVersion(for: $0) != nil }.count
    }

    /// Résumé annoncé à VoiceOver une fois chargé.
    var summary: String {
        if let errorMessage { return errorMessage }
        if !availableVersions.isEmpty && updateCount > 0 {
            return String(localized: "\(packages.count) paquets, \(updateCount) mises à jour disponibles")
        }
        return String(localized: "\(packages.count) paquets installés")
    }
}
