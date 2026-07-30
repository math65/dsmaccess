//
//  FeedbackCommands.swift
//  dsmaccess
//
//  Help menu item that opens the "Contact the developer" window.
//  Kept separate from AppCommands to limit conflicts with ongoing work on the
//  menus. The item disappears when the backend secret is not embedded in the
//  build.
//

import SwiftUI

struct FeedbackCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            if AppBackendClient.isConfigured {
                Button("feedback.menu.contact_developer") {
                    openWindow(id: "feedback")
                }
            }
        }
    }
}
