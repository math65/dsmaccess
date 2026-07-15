//
//  MainView.swift
//  dsmaccess
//
//  Fenêtre d'administration principale.
//

import AppKit
import SwiftUI

struct MainView: View {
    let session: SessionStore

    @Environment(AppSettings.self) private var settings
    @State private var selection = AppModule.systemInfo
    @State private var isRenamingNAS = false
    @State private var proposedNASName = ""

    init(session: SessionStore) {
        self.session = session
        _selection = State(
            initialValue: AppModule.allCases.first {
                $0.isAvailable(in: session.capabilities)
            } ?? .systemInfo
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(AppModuleSection.allCases) { section in
                    let modules = visibleModules(in: section)
                    if !modules.isEmpty {
                        Section(section.title) {
                            ForEach(modules) { module in
                                let available = module.isAvailable(in: session.capabilities)
                                Label {
                                    Text(module.title)
                                } icon: {
                                    Image(systemName: module.systemImage)
                                }
                                .tag(module)
                                .foregroundStyle(available ? .primary : .secondary)
                                .help(available ? Text(module.title) : Text(module.unavailableHelp))
                                .accessibilityLabel(sidebarLabel(for: module, available: available))
                                .accessibilityHint(available ? Text("") : Text(module.unavailableHelp))
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("DSM Access")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            moduleView
                .toolbar { commonToolbar }
        }
        .focusedSceneValue(\.selectedModule, $selection)
        .focusedSceneValue(\.availableModules, Set(visibleModules))
        .focusedSceneValue(
            \.sessionCommandActions,
            SessionCommandActions(
                profiles: session.profiles,
                activeProfileID: session.activeProfileID,
                logout: { Task { await logout() } },
                addNAS: addNAS,
                renameNAS: beginRenamingNAS,
                selectNAS: switchNAS
            )
        )
        .task {
            normalizeSelection()
            VoiceOver.announce(String(localized: "Connecté"), category: .navigation)
        }
        .onChange(of: visibleModules) { _, _ in
            normalizeSelection()
        }
        .onChange(of: selection) { _, module in
            VoiceOver.announce(module.localizedTitle, category: .navigation)
        }
        .alert("Renommer le NAS", isPresented: $isRenamingNAS) {
            TextField("Nom du NAS", text: $proposedNASName)
                .help("Saisir le nouveau nom du NAS")
            Button("Renommer", action: renameNAS)
                .disabled(proposedNASName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Enregistrer le nouveau nom du NAS")
            Button("Annuler", role: .cancel) { }
                .help("Annuler le changement de nom")
        } message: {
            Text("Choisissez le nom affiché dans DSM Access.")
        }
    }

    @ViewBuilder
    private var moduleView: some View {
        if !selection.isAvailable(in: session.capabilities) {
            UnavailableModuleView(module: selection)
        } else {
            availableModuleView
        }
    }

    @ViewBuilder
    private var availableModuleView: some View {
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

    private var visibleModules: [AppModule] {
        settings.sidebarOrder.filter { module in
            settings.enabledSidebarModules.contains(module)
                && (!settings.automaticallyHideUnavailableModules
                    || module.isAvailable(in: session.capabilities))
        }
    }

    private func visibleModules(in section: AppModuleSection) -> [AppModule] {
        visibleModules.filter { $0.section == section }
    }

    private func sidebarLabel(for module: AppModule, available: Bool) -> String {
        available
            ? module.localizedTitle
            : String(localized: "\(module.localizedTitle) (indisponible)")
    }

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button("Afficher ou masquer la barre latérale", systemImage: "sidebar.left", action: toggleSidebar)
                .help("Afficher ou masquer la barre latérale")
        }

        if session.profiles.count > 1 {
            ToolbarItem(placement: .primaryAction) {
                nasSelectionMenu
            }
        }
    }

    private var nasSelectionMenu: some View {
        Menu {
            ForEach(session.profiles) { profile in
                Button {
                    switchNAS(profile.id)
                } label: {
                    if profile.id == session.activeProfileID {
                        Label(profile.displayName, systemImage: "checkmark")
                    } else {
                        Text(profile.displayName)
                    }
                }
                .help(String(localized: "Se connecter à \(profile.displayName)"))
            }

            Divider()
            Button("Ajouter un NAS…", systemImage: "plus", action: addNAS)
                .help("Ajouter un NAS à DSM Access")
            Button("Renommer le NAS…", action: beginRenamingNAS)
                .help("Renommer le NAS connecté")
            Divider()
            Button("Déconnexion", role: .destructive) {
                Task { await logout() }
            }
            .help("Se déconnecter du NAS")
        } label: {
            Label(
                session.activeProfile?.displayName ?? String(localized: "NAS"),
                systemImage: "externaldrive.connected.to.line.below"
            )
        }
        .help("Changer de NAS")
    }

    private func normalizeSelection() {
        guard !visibleModules.contains(selection), let first = visibleModules.first else { return }
        selection = first
    }

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(
            #selector(NSSplitViewController.toggleSidebar(_:)),
            with: nil
        )
    }

    private func addNAS() {
        session.prepareNewNAS()
        Task { await session.logout() }
    }

    private func switchNAS(_ profileID: UUID) {
        guard profileID != session.activeProfileID else { return }
        session.prepareConnection(to: profileID)
        Task { await session.logout() }
    }

    private func beginRenamingNAS() {
        guard let profile = session.activeProfile else { return }
        proposedNASName = profile.displayName
        isRenamingNAS = true
    }

    private func renameNAS() {
        guard let profileID = session.activeProfileID else { return }
        session.renameProfile(profileID, to: proposedNASName)
        VoiceOver.announce(
            String(localized: "NAS renommé \(proposedNASName)"),
            category: .result
        )
    }

    private func logout() async {
        session.forgetActiveCredentials()
        await session.logout()
    }
}
