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
                String(localized: "module.unavailable.title", defaultValue: "\(module.localizedTitle) unavailable"),
                systemImage: module.systemImage
            )
        } description: {
            Text(module.unavailableHelp)
        } actions: {
            SettingsLink {
                Text("module.unavailable.edit_sidebar.button")
            }
            .help("module.unavailable.edit_sidebar.hint")
        }
        .task {
            VoiceOver.announce(
                String(localized: "module.unavailable.description", defaultValue: "\(module.localizedTitle) is not available on this NAS"),
                category: .navigation
            )
        }
    }
}
