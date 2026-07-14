//
//  AppCommands.swift
//  dsmaccess
//
//  Commandes de barre des menus reliées à la fenêtre active.
//

import SwiftUI

struct SessionCommandActions {
    let logout: () -> Void
}

private struct SelectedModuleKey: FocusedValueKey {
    typealias Value = Binding<AppModule>
}

private struct SessionCommandActionsKey: FocusedValueKey {
    typealias Value = SessionCommandActions
}

extension FocusedValues {
    var selectedModule: Binding<AppModule>? {
        get { self[SelectedModuleKey.self] }
        set { self[SelectedModuleKey.self] = newValue }
    }

    var sessionCommandActions: SessionCommandActions? {
        get { self[SessionCommandActionsKey.self] }
        set { self[SessionCommandActionsKey.self] = newValue }
    }
}

struct DSMCommands: Commands {
    @FocusedBinding(\.selectedModule) private var selectedModule
    @FocusedValue(\.sessionCommandActions) private var sessionActions

    var body: some Commands {
        CommandMenu("Navigation") {
            ForEach(AppModuleSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.modules) { module in
                        Button(module.title) {
                            selectedModule = module
                        }
                        .keyboardShortcut(module.keyboardShortcut, modifiers: .command)
                        .disabled(selectedModule == nil)
                    }
                }
            }
        }

        CommandGroup(before: .appTermination) {
            Button("Déconnexion") {
                sessionActions?.logout()
            }
            .disabled(sessionActions == nil)
        }
    }
}
