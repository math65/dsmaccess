//
//  RootView.swift
//  dsmaccess
//
//  Affiche la connexion ou l'interface d'administration selon l'état de la session.
//

import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if session.isLoggedIn {
                MainView(session: session)
            } else {
                LoginView(session: session)
            }
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}
