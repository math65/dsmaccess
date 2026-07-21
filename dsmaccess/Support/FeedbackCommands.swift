//
//  FeedbackCommands.swift
//  dsmaccess
//
//  Entrée du menu Aide ouvrant la fenêtre « Contacter le développeur ».
//  Fichier séparé d'AppCommands pour limiter les conflits avec les travaux en
//  cours sur les menus. L'entrée disparaît quand le secret du backend n'est pas
//  embarqué dans le build.
//

import SwiftUI

struct FeedbackCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            if AppBackendClient.isConfigured {
                Button("Contacter le développeur…") {
                    openWindow(id: "feedback")
                }
            }
        }
    }
}
