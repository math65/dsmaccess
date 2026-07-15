//
//  UnavailableModuleView.swift
//  dsmaccess
//

import SwiftUI

struct UnavailableModuleView: View {
    let module: AppModule
    var body: some View {
        ContentUnavailableView {
            Label(
                String(localized: "\(module.localizedTitle) indisponible"),
                systemImage: module.systemImage
            )
        } description: {
            Text(module.unavailableHelp)
        } actions: {
            SettingsLink {
                Text("Modifier la barre latérale…")
            }
            .help("Ouvrir les réglages de la barre latérale")
        }
        .task {
            VoiceOver.announce(
                String(localized: "\(module.localizedTitle) n’est pas disponible sur ce NAS"),
                category: .navigation
            )
        }
    }
}
