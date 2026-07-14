//
//  MainView.swift
//  dsmaccess
//
//  Écran principal une fois connecté : barre latérale listant les modules (Votre NAS,
//  Fichiers…) et zone de détail affichant le module choisi. Architecture extensible :
//  chaque futur module (utilisateurs, Docker…) ajoute un cas à `Module`.
//

import SwiftUI

struct MainView: View {
    let session: SessionStore
    @State private var selection: Module? = .systemInfo

    /// Modules disponibles dans la barre latérale.
    enum Module: Hashable, CaseIterable, Identifiable {
        case systemInfo
        case files
        case storage
        case shares
        case fileServices
        case packages
        case controlPanel

        var id: Self { self }

        var label: LocalizedStringKey {
            switch self {
            case .systemInfo: return "Votre NAS"
            case .files: return "Fichiers"
            case .storage: return "Stockage"
            case .shares: return "Partages"
            case .fileServices: return "Services de fichiers"
            case .packages: return "Centre de paquets"
            case .controlPanel: return "Panneau de configuration"
            }
        }

        var systemImage: String {
            switch self {
            case .systemInfo: return "server.rack"
            case .files: return "folder"
            case .storage: return "internaldrive"
            case .shares: return "externaldrive.badge.person.crop"
            case .fileServices: return "network"
            case .packages: return "shippingbox"
            case .controlPanel: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Module.allCases, selection: $selection) { module in
                Label(module.label, systemImage: module.systemImage)
            }
            .navigationTitle("DSM Access")
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    Task { await logout() }
                } label: {
                    Label("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityHint("Ferme la session sur le NAS")
                .padding()
            }
        } detail: {
            switch selection {
            case .systemInfo:
                SystemInfoView(session: session)
            case .files:
                FileBrowserView(session: session)
            case .storage:
                StorageView(session: session)
            case .shares:
                SharesView(session: session)
            case .fileServices:
                FileServicesView(session: session)
            case .packages:
                PackagesView(session: session)
            case .controlPanel:
                ControlPanelView(session: session)
            case nil:
                Text("Sélectionnez un module")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            VoiceOver.announce(String(localized: "Connecté"))
        }
    }

    private func logout() async {
        let endpoint = session.endpoint
        if let client = session.client, let sid = session.sid {
            try? await client.logout(sid: sid)
        }
        // Déconnexion volontaire : on oublie le mot de passe (pas de reconnexion auto ensuite).
        if let endpoint {
            CredentialStore.forget(account: Preferences.lastAccount, endpoint: endpoint)
        }
        session.clear()
    }
}
