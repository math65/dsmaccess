//
//  RootView.swift
//  dsmaccess
//
//  Aiguilleur : affiche l'écran de connexion tant qu'on n'est pas connecté,
//  puis l'écran de contenu (infos système) une fois la session ouverte.
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
