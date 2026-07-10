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

struct ResourceUsage: Decodable {
    let cpu: CPU?
    let memory: Memory?
    let network: [Interface]?

    /// Charges processeur en pourcentage (utilisateur / système / autre).
    struct CPU: Decodable {
        let userLoad: Int?
        let systemLoad: Int?
        let otherLoad: Int?

        enum CodingKeys: String, CodingKey {
            case userLoad = "user_load"
            case systemLoad = "system_load"
            case otherLoad = "other_load"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            userLoad = c.flexInt(.userLoad)
            systemLoad = c.flexInt(.systemLoad)
            otherLoad = c.flexInt(.otherLoad)
        }
    }

    /// Mémoire vive : pourcentage utilisé et tailles réelles/échange (en Kio).
    struct Memory: Decodable {
        let realUsage: Int?     // %
        let totalReal: Int?     // Kio
        let availReal: Int?     // Kio
        let swapUsage: Int?     // %

        enum CodingKeys: String, CodingKey {
            case realUsage = "real_usage"
            case totalReal = "total_real"
            case availReal = "avail_real"
            case swapUsage = "swap_usage"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            realUsage = c.flexInt(.realUsage)
            totalReal = c.flexInt(.totalReal)
            availReal = c.flexInt(.availReal)
            swapUsage = c.flexInt(.swapUsage)
        }
    }

    /// Débit d'une interface réseau (octets par seconde). DSM inclut une entrée
    /// synthétique `device == "total"` cumulant toutes les interfaces.
    struct Interface: Decodable {
        let device: String?
        let rx: Int?            // octets/s reçus
        let tx: Int?            // octets/s envoyés

        enum CodingKeys: String, CodingKey { case device, rx, tx }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            device = try? c.decode(String.self, forKey: .device)
            rx = c.flexInt(.rx)
            tx = c.flexInt(.tx)
        }
    }
}

// MARK: - Décodage souple

extension KeyedDecodingContainer {
    /// Décode un entier que DSM renvoie en nombre JSON ou en chaîne ("42"), sinon nil.
    func flexInt(_ key: Key) -> Int? {
        if let i = try? decode(Int.self, forKey: key) { return i }
        if let d = try? decode(Double.self, forKey: key) { return Int(d.rounded()) }
        if let s = try? decode(String.self, forKey: key) {
            if let i = Int(s) { return i }
            if let d = Double(s) { return Int(d.rounded()) }
        }
        return nil
    }
}
