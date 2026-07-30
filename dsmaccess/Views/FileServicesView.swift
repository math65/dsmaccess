//
//  FileServicesView.swift
//  dsmaccess
//  Management of the DSM file sharing protocols.

import SwiftUI

struct FileServicesView: View {
    @State private var vm: FileServicesViewModel
    @State private var pendingDisable: FileService?
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: FileServicesViewModel(session: session))
    }

    var body: some View {
        content
        .toolbar {
            ToolbarItem {
                Button {
                    reloadAll()
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("file_services.refresh.label")
            }
        }
        .task {
            await load(restoresInitialFocus: true)
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
            .accessibilityLabel("common.module.file_services")
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
            VoiceOver.announce(msg, priority: .high)
        }
    }

    private func reloadAll() {
        Task { await load() }
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
