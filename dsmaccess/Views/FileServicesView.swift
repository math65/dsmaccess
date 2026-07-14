//
//  FileServicesView.swift
//  dsmaccess
//
//  Module « Services de fichiers » (Panneau de configuration) : active/désactive les
//  protocoles de partage (SMB, NFS, FTP). Liste plate d'actions → List SwiftUI, comme
//  SharesView. Toute désactivation passe par une confirmation (couper SMB coupe l'accès
//  Finder, y compris celui de cet appareil).
//

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
        .navigationTitle("Services de fichiers")
        .toolbar {
            ToolbarItem {
                Button {
                    reloadAll()
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser l’état des services")
            }
        }
        .task {
            focusContent = true
            await vm.load()
            guard !Task.isCancelled else { return }
            focusContent = true
            VoiceOver.announce(vm.summary)
        }
        .confirmationDialog(
            "Désactiver ce service ?",
            isPresented: Binding(
                get: { pendingDisable != nil },
                set: { if !$0 { pendingDisable = nil } }
            ),
            presenting: pendingDisable
        ) { service in
            Button("Désactiver \(service.displayName)", role: .destructive) {
                apply(service, enabled: false)
            }
            Button("Annuler", role: .cancel) { }
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
                    Text("Activez ou désactivez les protocoles de partage de fichiers du NAS.")
                        .foregroundStyle(.secondary)
                }
                Section("Protocoles") {
                    ForEach(vm.services) { service in
                        row(for: service)
                    }
                }
            }
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
    }

    @ViewBuilder
    private func control(for service: FileService, state: FileServiceState) -> some View {
        let isBusy = vm.busy.contains(service)
        switch state {
        case .on:
            Button("Désactiver") { pendingDisable = service }
                .disabled(isBusy)
                .accessibilityLabel("Désactiver \(service.displayName)")
        case .off:
            Button("Activer") { apply(service, enabled: true) }
                .disabled(isBusy)
                .accessibilityLabel("Activer \(service.displayName)")
        case .unknown, .failed:
            Button("Réessayer") { reloadAll() }
                .disabled(isBusy)
                .accessibilityLabel("Réessayer \(service.displayName)")
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
        Task {
            focusContent = true
            await vm.load()
            guard !Task.isCancelled else { return }
            VoiceOver.announce(vm.summary)
        }
    }

    // MARK: - Présentation

    private func stateText(_ state: FileServiceState) -> String {
        switch state {
        case .on: return String(localized: "Activé")
        case .off: return String(localized: "Désactivé")
        case .unknown: return String(localized: "État indisponible")
        case .failed(let message): return message
        }
    }

    private func stateColor(_ state: FileServiceState) -> Color {
        switch state {
        case .on: return .green
        case .off: return .gray
        case .unknown: return .orange
        case .failed: return .red
        }
    }

    private func disableWarning(for service: FileService) -> String {
        if service == .smb {
            return String(localized: "SMB est le protocole utilisé par le Finder et l'Explorateur Windows. Le désactiver coupera l'accès aux fichiers depuis ces apps, y compris depuis cet appareil. Vous pourrez le réactiver ici.")
        }
        return String(localized: "Le service sera arrêté et les connexions en cours interrompues. Vous pourrez le réactiver ici.")
    }
}
