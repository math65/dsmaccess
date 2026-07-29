//
//  ResourceUsage.swift
//  dsmaccess
//
//  Charge utile de SYNO.Core.System.Utilization (method=get) : mesures instantanées
//  du NAS (processeur, mémoire, réseau). API NON documentée : structure calée sur des
//  réponses réelles, champs optionnels par prudence. Les nombres arrivent tantôt en
//  entier JSON tantôt en chaîne selon la version de DSM → décodage souple (`flexInt`).
//

import Foundation

struct ResourceUsage: nonisolated Decodable, Sendable {
    let cpu: CPU?
    let memory: Memory?
    let network: [Interface]?
    let disk: Activity?
    let space: Activity?

    enum CodingKeys: String, CodingKey { case cpu, memory, network, disk, space }

    /// Activité d'un groupe de périphériques. DSM emploie la même forme pour les disques
    /// (`disk`, chacun avec son `type`) et pour les volumes (`space`), avec dans les deux
    /// cas une entrée cumulée `device == "total"` à part.
    struct Activity: nonisolated Decodable, Sendable {
        let devices: [Device]
        let total: Device?

        enum CodingKeys: String, CodingKey { case disk, volume, total }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            devices = (try? c.decode([Device].self, forKey: .disk))
                ?? (try? c.decode([Device].self, forKey: .volume))
                ?? []
            total = try? c.decode(Device.self, forKey: .total)
        }
    }

    /// Un disque ou un volume. `read_byte`/`write_byte` sont des débits en octets par
    /// seconde, `read_access`/`write_access` des nombres d'accès, `utilization` un
    /// pourcentage.
    struct Device: nonisolated Decodable, Sendable, Identifiable {
        let device: String?
        let displayName: String?
        let type: String?
        let utilization: Int?
        let readBytesPerSecond: Int?
        let writeBytesPerSecond: Int?
        let readOperations: Int?
        let writeOperations: Int?

        var id: String { device ?? displayName ?? "" }
        /// Nom lisible, avec repli sur l'identifiant matériel quand DSM n'en donne pas.
        var name: String { displayName ?? device ?? "" }

        enum CodingKeys: String, CodingKey {
            case device, type, utilization
            case displayName = "display_name"
            case readBytesPerSecond = "read_byte"
            case writeBytesPerSecond = "write_byte"
            case readOperations = "read_access"
            case writeOperations = "write_access"
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            device = c.flexString(.device)
            displayName = c.flexString(.displayName)
            type = c.flexString(.type)
            utilization = c.flexInt(.utilization)
            readBytesPerSecond = c.flexInt(.readBytesPerSecond)
            writeBytesPerSecond = c.flexInt(.writeBytesPerSecond)
            readOperations = c.flexInt(.readOperations)
            writeOperations = c.flexInt(.writeOperations)
        }
    }

    /// Charges processeur en pourcentage (utilisateur / système / autre), et les moyennes
    /// de charge Unix. Celles-ci arrivent **multipliées par cent** (`57` vaut 0,57) : le
    /// client web de DSM les divise avant affichage, contrat relevé dans son code.
    struct CPU: nonisolated Decodable, Sendable {
        let userLoad: Int?
        let systemLoad: Int?
        let otherLoad: Int?
        let oneMinuteLoad: Double?
        let fiveMinuteLoad: Double?
        let fifteenMinuteLoad: Double?

        enum CodingKeys: String, CodingKey {
            case userLoad = "user_load"
            case systemLoad = "system_load"
            case otherLoad = "other_load"
            case oneMinuteLoad = "1min_load"
            case fiveMinuteLoad = "5min_load"
            case fifteenMinuteLoad = "15min_load"
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userLoad = c.flexInt(.userLoad)
            systemLoad = c.flexInt(.systemLoad)
            otherLoad = c.flexInt(.otherLoad)
            oneMinuteLoad = c.flexInt(.oneMinuteLoad).map { Double($0) / 100 }
            fiveMinuteLoad = c.flexInt(.fiveMinuteLoad).map { Double($0) / 100 }
            fifteenMinuteLoad = c.flexInt(.fifteenMinuteLoad).map { Double($0) / 100 }
        }
    }

    /// Mémoire vive : pourcentage utilisé et tailles réelles/échange (en Kio).
    struct Memory: nonisolated Decodable, Sendable {
        let realUsage: Int?     // %
        let totalReal: Int?     // Kio
        let availReal: Int?     // Kio
        let cached: Int?        // Kio
        let buffer: Int?        // Kio
        let swapUsage: Int?     // %

        /// Mémoire réellement occupée, cache et tampons exclus. C'est la définition de DSM :
        /// sur un NAS où le cache disque occupe presque toute la mémoire, compter le cache
        /// donnerait 96 % là où DSM annonce 17 %, et les deux chiffres se contrediraient
        /// à l'écran. Vérifié sur DSM 7.4 le 29/07/2026.
        var usedReal: Int? {
            guard let totalReal, let availReal else { return nil }
            let used = totalReal - availReal - (cached ?? 0) - (buffer ?? 0)
            return used >= 0 ? used : nil
        }

        enum CodingKeys: String, CodingKey {
            case realUsage = "real_usage"
            case totalReal = "total_real"
            case availReal = "avail_real"
            case swapUsage = "swap_usage"
            case cached, buffer
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            realUsage = c.flexInt(.realUsage)
            totalReal = c.flexInt(.totalReal)
            availReal = c.flexInt(.availReal)
            cached = c.flexInt(.cached)
            buffer = c.flexInt(.buffer)
            swapUsage = c.flexInt(.swapUsage)
        }
    }

    /// Débit d'une interface réseau (octets par seconde). DSM inclut une entrée
    /// synthétique `device == "total"` cumulant toutes les interfaces.
    struct Interface: nonisolated Decodable, Sendable {
        let device: String?
        let rx: Int?            // octets/s reçus
        let tx: Int?            // octets/s envoyés

        enum CodingKeys: String, CodingKey { case device, rx, tx }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            device = try? c.decode(String.self, forKey: .device)
            rx = c.flexInt(.rx)
            tx = c.flexInt(.tx)
        }
    }
}
