//
//  ControlPanelSection.swift
//  dsmaccess
//
//  Sections available in the Control Panel.
//

import SwiftUI

enum ControlPanelSection: Hashable, CaseIterable, Identifiable {
    case network
    case externalDevices
    case dsmUpdate

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .network: "common.section.network_identity"
        case .externalDevices: "external_devices.title"
        case .dsmUpdate: "common.section.dsm_update"
        }
    }

    var localizedTitle: String {
        switch self {
        case .network: String(localized: "common.section.network_identity")
        case .externalDevices: String(localized: "external_devices.title")
        case .dsmUpdate: String(localized: "common.section.dsm_update")
        }
    }

    var systemImage: String {
        switch self {
        case .network: "network"
        case .externalDevices: "externaldrive"
        case .dsmUpdate: "arrow.down.circle"
        }
    }

    var hint: LocalizedStringKey {
        switch self {
        case .network: "control_panel.network.description"
        case .externalDevices: "control_panel.external_devices.description"
        case .dsmUpdate: "control_panel.dsm_update.description"
        }
    }
}
