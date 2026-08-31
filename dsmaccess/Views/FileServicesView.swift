//
//  FileServicesView.swift
//  dsmaccess
//  Management of the DSM file sharing protocols.

import SwiftUI

struct FileServicesView: View {
    /// Tabs of the screen, in DSM's own order. SMB comes first: it is the protocol Finder and
    /// Windows Explorer use. The other protocols share one tab until each gets its own,
    /// measured contract.
    private enum Tab: Hashable {
        case smb
        case otherProtocols
    }

    @State private var vm: FileServicesViewModel
    @State private var smb: SMBSettingsViewModel
    @State private var tab: Tab = .smb
    @State private var pendingDisable: FileService?
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: FileServicesViewModel(session: session))
        _smb = State(initialValue: SMBSettingsViewModel(session: session))
    }

    var body: some View {
        // Wrapped in a VStack for the same reason as the resource monitor: at the root of the
        // pane, macOS lifts the tabs into the toolbar, where VoiceOver reads them as a radio
        // group sitting between the sidebar and refresh buttons rather than as tabs.
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                SMBSettingsPane(vm: smb)
                    .tabItem { Text("file_services.tab.smb") }
                    .tag(Tab.smb)
                content
                    .tabItem { Text("file_services.tab.other_protocols") }
                    .tag(Tab.otherProtocols)
                    .task { await load(restoresInitialFocus: true) }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    refreshVisibleTab()
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("file_services.refresh.label")
            }
        }
        .confirmationDialog(
            "file_services.disable.confirm",
            isPresented: Binding(
                get: { pendingDisable != nil },
                set: { if !$0 { pendingDisable = nil } }
            ),
            presenting: pendingDisable
        ) { service in
            Button(String(localized: "files.service.disable.button", defaultValue: "Disable \(service.displayName)"), role: .destructive) {
                apply(service, enabled: false)
            }
            .help(String(localized: "files.service.disable.button", defaultValue: "Disable \(service.displayName)"))
            Button("common.button.cancel", role: .cancel) { }
                .help("file_services.disable.cancel")
        } message: { service in
            Text(disableWarning(for: service))
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.states.isEmpty {
            ModuleLoadingView()
                .accessibilityFocused($focusContent)
        } else {
            List {
                Section {
                    Text("file_services.protocols.description")
                        .foregroundStyle(.readableSecondary)
                }
                Section("file_services.section.protocols") {
                    ForEach(vm.services) { service in
                        row(for: service)
                    }
                }
            }
            .accessibilityLabel("file_services.other_protocols.label")
            .accessibilityFocused($focusContent)
        }
    }

    private func row(for service: FileService) -> some View {
        let state = vm.states[service] ?? .unknown
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName).fontWeight(.medium)
                Text(stateText(state))
                    .font(.caption)
                    .foregroundStyle(stateColor(state))
            }
            Spacer()
            control(for: service, state: state)
        }
        .contextMenu {
            switch state {
            case .on:
                Button(String(localized: "files.service.disable.button", defaultValue: "Disable \(service.displayName)")) { pendingDisable = service }
                    .disabled(vm.busy.contains(service))
                    .help(String(localized: "files.service.disable.button", defaultValue: "Disable \(service.displayName)"))
            case .off:
                Button(String(localized: "file_services.service.enable.action", defaultValue: "Enable \(service.displayName)")) { apply(service, enabled: true) }
                    .disabled(vm.busy.contains(service))
                    .help(String(localized: "file_services.service.enable.action", defaultValue: "Enable \(service.displayName)"))
            case .unknown, .failed:
                Button("common.button.retry") { reloadAll() }
                    .disabled(vm.busy.contains(service))
                    .help(String(localized: "file_services.retry.hint", defaultValue: "Retry loading \(service.displayName)"))
            }
        }
    }

    @ViewBuilder
    private func control(for service: FileService, state: FileServiceState) -> some View {
        let isBusy = vm.busy.contains(service)
        switch state {
        case .on, .off:
            Toggle(
                String(localized: "file_services.service.enable.action", defaultValue: "Enable \(service.displayName)"),
                isOn: Binding(
                    get: { state == .on },
                    set: { enabled in
                        if enabled {
                            apply(service, enabled: true)
                        } else {
                            pendingDisable = service
                        }
                    }
                )
            )
                .labelsHidden()
                .disabled(isBusy)
                .accessibilityLabel(service.displayName)
                .accessibilityValue(stateText(state))
                .accessibilityHint("file_services.service.toggle.hint")
                .help(String(localized: "file_services.service.toggle.label", defaultValue: "Enable or disable \(service.displayName)"))
        case .unknown, .failed:
            Button("common.button.retry") { reloadAll() }
                .disabled(isBusy)
                .accessibilityLabel(String(localized: "file_services.retry.button", defaultValue: "Retry \(service.displayName)"))
                .help(String(localized: "file_services.retry.hint", defaultValue: "Retry loading \(service.displayName)"))
        }
    }

    // MARK: - Actions

    private func apply(_ service: FileService, enabled: Bool) {
        Task {
            let msg = await vm.setEnabled(service, enabled)
            OperationFailures.shared.present(msg, from: .fileServices)
        }
    }

    private func reloadAll() {
        Task { await load() }
    }

    /// The toolbar button reloads what is on screen, not both tabs: the two read different
    /// APIs, and refreshing a tab the user cannot see would announce a result about it.
    private func refreshVisibleTab() {
        switch tab {
        case .smb:
            Task {
                VoiceOver.announce(
                    String(localized: "smb.loading"),
                    category: .progress,
                    priority: .low
                )
                await smb.load()
                guard !Task.isCancelled else { return }
                VoiceOver.announce(
                    smb.summary,
                    category: smb.loadError == nil ? .result : .error
                )
            }
        case .otherProtocols:
            reloadAll()
        }
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "file_services.loading"),
            category: .progress,
            priority: .low
        )
        await vm.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        }
        VoiceOver.announce(
            vm.summary,
            category: vm.hasFailures ? .error : .result
        )
    }

    // MARK: - Presentation

    private func stateText(_ state: FileServiceState) -> String {
        switch state {
        case .on: return String(localized: "common.status.enabled.masculine")
        case .off: return String(localized: "common.status.disabled.masculine")
        case .unknown: return String(localized: "file_services.status.unavailable")
        case .failed(let message): return message
        }
    }

    private func stateColor(_ state: FileServiceState) -> Color {
        switch state {
        case .on: return .readableGreen
        case .off: return .readableSecondary
        case .unknown: return .readableOrange
        case .failed: return .readableRed
        }
    }

    private func disableWarning(for service: FileService) -> String {
        if service == .smb {
            return String(localized: "file_services.smb.disable.confirm.description")
        }
        return String(localized: "file_services.disable.confirm.description")
    }
}
