//
//  SettingsWindowConfigurator.swift
//  dsmaccess
//
//  Applique aux onglets de la scène Settings les conventions macOS que
//  SwiftUI n'expose pas directement : barre fixe et info-bulles natives.
//

import AppKit
import SwiftUI

struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        configureWindow(containing: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(containing: nsView)
    }

    private func configureWindow(containing view: NSView) {
        Task { @MainActor [weak view] in
            await Task.yield()
            guard let toolbar = view?.window?.toolbar else { return }
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false

            for item in toolbar.items {
                guard let pane = AppSettingsPane.allCases.first(where: {
                    $0.localizedTitle == item.label
                }) else { continue }
                item.toolTip = pane.localizedHelp
            }
        }
    }
}
