//
//  MainView.swift
//  dsmaccess
//
//  Main administration window.
//

import SwiftUI

struct MainView: View {
    let session: SessionStore

    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection = AppModule.systemInfo
    @State private var isRenamingNAS = false
    @State private var proposedNASName = ""
    /// External storage is owned here rather than in its screen: the toolbar menu has to know
    /// about a plugged-in device without the Control Panel ever having been opened.
    @State private var externalDevices: ExternalDevicesViewModel
    @State private var requestedControlPanelSection: ControlPanelSection?
    @AccessibilityFocusState private var sidebarFocusedModule: AppModule?
    @AccessibilityFocusState private var focusReconnectionNotice: Bool

    init(session: SessionStore) {
        self.session = session
        _selection = State(
            initialValue: AppModule.allCases.first {
                $0.isAvailable(in: session.capabilities)
            } ?? .systemInfo
        )
        _externalDevices = State(initialValue: ExternalDevicesViewModel(session: session))
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
                                .accessibilityFocused($sidebarFocusedModule, equals: module)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("main.modules.label")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            moduleView
        }
        .navigationTitle(selection.title)
        .toolbar { commonToolbar }
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
            VoiceOver.announce(String(localized: "common.status.connected"), category: .navigation)
            await externalDevices.load()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the app is when a drive has just been plugged in. The reload is
            // silent: VoiceOver must not comment on a refresh nobody asked for.
            guard phase == .active else { return }
            Task { await externalDevices.load() }
        }
        .onChange(of: visibleModules) { _, _ in
            normalizeSelection()
        }
        .onChange(of: selection) { _, module in
            VoiceOver.announce(module.localizedTitle, category: .navigation)
        }
        .task(id: selection) {
            // Let SwiftUI finish replacing the destination and its toolbar before
            // restoring the VoiceOver cursor to the row that initiated navigation.
            await Task.yield()
            guard session.reconnectionNotice == nil else { return }
            sidebarFocusedModule = selection
        }
        .safeAreaInset(edge: .top, spacing: 0) { reconnectionNoticeBanner }
        .alert("main.rename.title", isPresented: $isRenamingNAS) {
            TextField("common.field.nas_name", text: $proposedNASName)
                .help("main.rename.field.label")
            Button("common.button.rename", action: renameNAS)
                .disabled(proposedNASName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("common.button.save_nas_name")
            Button("common.button.cancel", role: .cancel) { }
                .help("main.rename.cancel")
        } message: {
            Text("main.rename.description")
        }
    }

    /// Reports that a session expiration interrupted the work in progress, because the
    /// automatic reconnection brings the user back here with no visible detour through the
    /// sign-in screen.
    @ViewBuilder
    private var reconnectionNoticeBanner: some View {
        if let notice = session.reconnectionNotice {
            HStack {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.readableOrange)
                    .accessibilityFocused($focusReconnectionNotice)
                Spacer()
                Button("main.notice.dismiss") {
                    session.dismissReconnectionNotice()
                    sidebarFocusedModule = selection
                }
                .help("main.notice.reconnect.dismiss.hint")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Opaque background: the banner floats above the window's columns.
            .background(.bar)
            .onAppear {
                VoiceOver.announce(notice, category: .error, priority: .high)
                focusReconnectionNotice = true
            }
        }
    }

    @ViewBuilder
    private var moduleView: some View {
        if !selection.isAvailable(in: session.capabilities) {
            UnavailableModuleView(module: selection, session: session)
        } else {
            availableModuleView
        }
    }

    @ViewBuilder
    private var availableModuleView: some View {
        switch selection {
        case .systemInfo:
            SystemInfoView(session: session)
        case .resourceMonitor:
            ResourceMonitorView(session: session)
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
        case .usbCopy:
            USBCopyView(session: session)
        case .hyperBackup:
            HyperBackupView(session: session)
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
        case .controlPanel:
            ControlPanelView(
                session: session,
                externalDevices: externalDevices,
                requestedSection: $requestedControlPanelSection
            )
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
            : String(localized: "main.module.unavailable", defaultValue: "\(module.localizedTitle) (unavailable)")
    }

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        if externalDevices.hasDevices {
            ToolbarItem(placement: .primaryAction) {
                externalDevicesMenu
            }
        }
        if session.profiles.count > 1 {
            ToolbarItem(placement: .primaryAction) {
                nasSelectionMenu
            }
        }
    }

    /// Mirrors DSM's own eject tray: it only exists while something is plugged in, and it puts
    /// ejecting one keystroke away from wherever the user happens to be.
    private var externalDevicesMenu: some View {
        Menu {
            ForEach(externalDevices.devices) { device in
                Button {
                    Task { await externalDevices.eject(device) }
                } label: {
                    Text(
                        String(
                            localized: "external_devices.menu.eject_device",
                            defaultValue: "Eject \(device.displayName)"
                        )
                    )
                }
                .disabled(externalDevices.isBusy(device))
            }
            Divider()
            Button("external_devices.menu.settings") {
                selection = .controlPanel
                requestedControlPanelSection = .externalDevices
            }
            .disabled(!AppModule.controlPanel.isAvailable(in: session.capabilities))
        } label: {
            Label("external_devices.menu.label", systemImage: "eject")
        }
        .help("external_devices.menu.hint")
        .accessibilityLabel("external_devices.menu.label")
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
                .help(String(localized: "common.action.connect_to", defaultValue: "Connect to \(profile.displayName)"))
            }

            Divider()
            Button("common.action.add_nas", systemImage: "plus", action: addNAS)
                .help("common.action.add_nas.hint")
            Button("common.action.rename_nas", action: beginRenamingNAS)
                .help("common.action.rename_nas.hint")
            Divider()
            Button("common.action.log_out", role: .destructive) {
                Task { await logout() }
            }
            .help("common.action.log_out.hint")
        } label: {
            Label(
                session.activeProfile?.displayName ?? String(localized: "common.label.nas"),
                systemImage: "externaldrive.connected.to.line.below"
            )
        }
        .help("main.nas.switch")
        // The toolbar reduces this menu to its icon: without an explicit label, VoiceOver
        // announces the SF Symbol name instead of the NAS name.
        .accessibilityLabel("main.nas.switch")
        .accessibilityValue(session.activeProfile?.displayName ?? String(localized: "main.nas.none"))
    }

    private func normalizeSelection() {
        guard !visibleModules.contains(selection), let first = visibleModules.first else { return }
        selection = first
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
            String(localized: "common.status.nas_renamed", defaultValue: "NAS renamed \(proposedNASName)"),
            category: .result
        )
    }

    private func logout() async {
        session.forgetActiveCredentials()
        await session.logout()
    }
}
