//
//  ControlPanelSection.swift
//  dsmaccess
//
//  Sections available in the Control Panel.
//

import SwiftUI

enum ControlPanelSection: Hashable, CaseIterable, Identifiable {
    case network
    case dsmUpdate

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .network: "common.section.network_identity"
        case .dsmUpdate: "common.section.dsm_update"
        }
    }

    var localizedTitle: String {
        switch self {
        case .network: String(localized: "common.section.network_identity")
        case .dsmUpdate: String(localized: "common.section.dsm_update")
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
        case .network: "control_panel.network.description"
        case .dsmUpdate: "control_panel.dsm_update.description"
        }
    }
}
