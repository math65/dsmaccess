//
//  DSMUpgrade.swift
//  dsmaccess
//
//  Mise à jour manuelle de DSM à partir d'un fichier .pat (SYNO.Core.Upgrade).
//

import Foundation

/// Ce que DSM annonce du fichier reçu avant d'installer quoi que ce soit.
///
/// Le flux a été relevé sur DSM 7.4 en observant le client web, mais la forme exacte des
/// réponses n'a pas pu être mesurée. Le décodage accepte donc plusieurs écritures et ne
/// considère aucun champ comme obligatoire : une réponse inattendue doit laisser l'écran
/// utilisable, pas interrompre l'opération.
struct DSMUpgradePreCheck: nonisolated Decodable, Equatable, Sendable {
    /// Paquets que DSM cessera de prendre en charge après la mise à jour.
    let unsupportedPackages: [String]
    /// Vrai quand DSM a répondu dans une forme que l'app sait lire. Faux, l'écran renvoie
    /// l'utilisateur vers DSM plutôt que d'affirmer qu'il n'y a aucune conséquence.
    let isUnderstood: Bool

    enum CodingKeys: String, CodingKey {
        case unsupportedPackages = "unsupported_packages"
        case removePackages = "remove_packages"
        case breakPackages = "break_pkgs"
        case packages
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var noms: [String] = []
        var reconnu = false
        for key in [CodingKeys.unsupportedPackages, .removePackages, .breakPackages, .packages] {
            guard let listed = Self.names(in: values, forKey: key) else { continue }
            reconnu = true
            noms.append(contentsOf: listed)
        }
        unsupportedPackages = Array(Set(noms)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        isUnderstood = reconnu
    }

    init(unsupportedPackages: [String], isUnderstood: Bool) {
        self.unsupportedPackages = unsupportedPackages
        self.isUnderstood = isUnderstood
    }

    /// DSM écrit ce genre de liste tantôt en chaînes, tantôt en objets nommés.
    private static func names(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> [String]? {
        if let plain = try? container.decode([String].self, forKey: key) {
            return plain.filter { !$0.isEmpty }
        }
        if let objects = try? container.decode([NamedPackage].self, forKey: key) {
            return objects.compactMap(\.resolvedName)
        }
        return nil
    }

    private struct NamedPackage: nonisolated Decodable {
        let resolvedName: String?

        enum CodingKeys: String, CodingKey {
            case name
            case displayName = "display_name"
            case packageID = "package"
        }

        nonisolated init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            resolvedName = values.flexString(.displayName)
                ?? values.flexString(.name)
                ?? values.flexString(.packageID)
        }
    }
}

/// Avancement renvoyé par `SYNO.Core.Upgrade` pendant l'installation. Aucun champ n'est
/// garanti : l'écran se contente de ce qu'il obtient et n'invente pas de progression.
struct DSMUpgradeProgress: nonisolated Decodable, Equatable, Sendable {
    let percentage: Int?
    let isFinished: Bool

    enum CodingKeys: String, CodingKey {
        case progress
        case percent
        case status
        case finished
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let brut = values.flexInt(.progress) ?? values.flexInt(.percent)
        percentage = brut.map { min(max($0, 0), 100) }
        let status = values.flexString(.status)?.lowercased()
        isFinished = values.flexBool(.finished)
            ?? (status.map { ["done", "finished", "complete", "completed"].contains($0) } ?? false)
    }

    init(percentage: Int?, isFinished: Bool) {
        self.percentage = percentage
        self.isFinished = isFinished
    }
}

/// Réponse de `/webman/pingpong.cgi`, le signal que DSM utilise lui-même pour savoir si le
/// NAS a fini de démarrer.
///
/// ⚠️ Mesuré le 2026-07-28 : `boot_done` passe à `true` alors que l'interface de DSM affiche
/// encore plusieurs minutes de redémarrage. Il dit que l'hôte répond, pas que la mise à jour
/// est terminée — seule une reconnexion réussie le prouve.
struct DSMBootState: nonisolated Decodable, Equatable, Sendable {
    let isBootDone: Bool

    enum CodingKeys: String, CodingKey {
        case bootDone = "boot_done"
        case success
    }

    nonisolated init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isBootDone = values.flexBool(.bootDone) ?? false
    }

    init(isBootDone: Bool) {
        self.isBootDone = isBootDone
    }
}
