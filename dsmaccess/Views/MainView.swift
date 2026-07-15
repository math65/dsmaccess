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
                            let available = module.isAvailable(in: session.capabilities)
                            Label(module.title, systemImage: module.systemImage)
                                .tag(module)
                                .disabled(!available)
                                .foregroundStyle(available ? .primary : .secondary)
                                .help(available ? Text(module.title) : Text(module.unavailableHelp))
                                .accessibilityValue(available ? "" : String(localized: "Non disponible"))
                                .accessibilityHint(available ? Text("") : Text(module.unavailableHelp))
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
        .focusedSceneValue(\.availableModules, availableModules)
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
        case .logsSecurity:
            LogsSecurityView(session: session)
        case .files:
            FileBrowserView(session: session)
        case .shares:
            SharesView(session: session)
        case .downloads:
            DownloadStationView(session: session)
        case .usersGroups:
            UsersGroupsView(session: session)
        case .fileServices:
            FileServicesView(session: session)
        case .packages:
            PackagesView(session: session)
        case .containers:
            ContainersView(session: session)
        case .virtualMachines:
            VirtualMachinesView(session: session)
        case .surveillance:
            SurveillanceView(session: session)
        }
    }

    private var availableModules: Set<AppModule> {
        Set(AppModule.allCases.filter { $0.isAvailable(in: session.capabilities) })
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
        await session.logout()
        if let endpoint {
            CredentialStore.forget(account: Preferences.lastAccount, endpoint: endpoint)
        }
    }
}
