//
//  NetworkInfo.swift
//  dsmaccess
//
//  Réponse de SYNO.Core.Network (method=get) : identité et configuration réseau du NAS.
//  Champs vérifiés sur DSM 7.4 ; tous optionnels (DSM en renvoie davantage qu'on n'en lit).
//

import Foundation

struct NetworkInfo: Decodable {
    /// Nom du serveur (celui affiché sur le réseau, ex. SMB/Time Machine).
    let serverName: String?
    /// Passerelle par défaut (IPv4).
    let gateway: String?
    let dnsPrimary: String?
    let dnsSecondary: String?
    /// true : serveurs DNS saisis manuellement ; false : fournis par le DHCP.
    let dnsManual: Bool?
    /// Passerelle IPv6 (vide si IPv6 non configuré).
    let v6gateway: String?
    /// Rattachement à un domaine Windows.
    let enableWinDomain: Bool?
    /// Interface réseau principale (celle qui porte la passerelle).
    let gatewayInfo: Interface?

    struct Interface: Decodable {
        let ifname: String?
        let ip: String?
        let mask: String?
        let status: String?
        let type: String?
        let useDhcp: Bool?

        enum CodingKeys: String, CodingKey {
            case ifname, ip, mask, status, type
            case useDhcp = "use_dhcp"
        }
    }

    enum CodingKeys: String, CodingKey {
        case serverName = "server_name"
        case gateway
        case dnsPrimary = "dns_primary"
        case dnsSecondary = "dns_secondary"
        case dnsManual = "dns_manual"
        case v6gateway
        case enableWinDomain = "enable_windomain"
        case gatewayInfo = "gateway_info"
    }
}
