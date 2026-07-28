//
//  ControlPanelSection.swift
//  dsmaccess
//
//  Sections disponibles dans le Panneau de configuration.
//

import SwiftUI

enum ControlPanelSection: Hashable, CaseIterable, Identifiable {
    case network
    case dsmUpdate

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .network: "Réseau et identité"
        case .dsmUpdate: "Mise à jour de DSM"
        }
    }

    var localizedTitle: String {
        switch self {
        case .network: String(localized: "Réseau et identité")
        case .dsmUpdate: String(localized: "Mise à jour de DSM")
        }
    }

    var systemImage: String {
        switch self {
        case .network: "network"
        case .dsmUpdate: "arrow.down.circle"
        }
    }

    var hint: LocalizedStringKey {
        switch self {
        case .network: "Nom du serveur, adresse IP, passerelle et DNS"
        case .dsmUpdate: "Installer une mise à jour de DSM depuis un fichier"
        }
    }
}
