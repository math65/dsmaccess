//
//  MainView.swift
//  dsmaccess
//
//  Fenêtre d'administration principale.
//

import SwiftUI

struct MainView: View {
    let session: SessionStore

    @State private var selection = AppModule.systemInfo

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(AppModuleSection.allCases) { section in
                    Section(section.title) {
                        ForEach(section.modules) { module in
                            Label(module.title, systemImage: module.systemImage)
                                .tag(module)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("DSM Access")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            moduleView
                .toolbar { accountToolbar }
        }
        .focusedSceneValue(\.selectedModule, $selection)
        .focusedSceneValue(
            \.sessionCommandActions,
            SessionCommandActions { Task { await logout() } }
        )
        .task {
            VoiceOver.announce(String(localized: "Connecté"))
        }
    }

    @ViewBuilder
    private var moduleView: some View {
        switch selection {
        case .systemInfo:
            SystemInfoView(session: session)
        case .storage:
            StorageView(session: session)
        case .files:
            FileBrowserView(session: session)
        case .shares:
            SharesView(session: session)
        case .fileServices:
            FileServicesView(session: session)
        case .packages:
            PackagesView(session: session)
        }
    }

    @ToolbarContentBuilder
    private var accountToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let endpoint = session.endpoint {
                    Text("\(endpoint.host):\(endpoint.port)")
                }
                Divider()
                Button("Déconnexion", role: .destructive) {
                    Task { await logout() }
                }
            } label: {
                Label("Session", systemImage: "person.crop.circle")
            }
            .help("Gérer la session DSM")
        }
    }

    private func logout() async {
        let endpoint = session.endpoint
        if let client = session.client, let sid = session.sid {
            try? await client.logout(sid: sid)
        }
        if let endpoint {
            CredentialStore.forget(account: Preferences.lastAccount, endpoint: endpoint)
        }
        session.clear()
    }
}
