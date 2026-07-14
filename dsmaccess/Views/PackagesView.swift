//
//  PackagesView.swift
//  dsmaccess
//
//  Module « Centre de paquets » : liste (lecture seule) les paquets installés du NAS
//  (SYNO.Core.Package), avec leur version et leur état. La mise à jour viendra ensuite.
//

import SwiftUI

struct PackagesView: View {
    @State private var vm: PackagesViewModel
    @State private var pendingUninstall: PackageInfo?
    @State private var showSettings = false
    @AccessibilityFocusState private var focusContent: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _vm = State(initialValue: PackagesViewModel(session: session))
    }

    var body: some View {
        content
        .navigationTitle("Centre de paquets")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showSettings = true
                } label: {
                    Label("Réglages du Centre de paquets", systemImage: "gearshape")
                }
                .help("Réglages du Centre de paquets")

                Button {
                    Task { await load() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser les paquets")
            }
        }
        .task {
            await load()
        }
        .confirmationDialog(
            "Désinstaller ce paquet ?",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            presenting: pendingUninstall
        ) { package in
            Button("Désinstaller \(package.displayName)", role: .destructive) {
                requestUninstall(package)
            }
            Button("Annuler", role: .cancel) { }
        } message: { package in
            Text(uninstallWarning(for: package))
        }
        .sheet(isPresented: $showSettings) {
            PackageSettingsSheet(session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.packages.isEmpty {
            ModuleLoadingView()
                .accessibilityFocused($focusContent)
        } else if let error = vm.errorMessage {
            ModuleErrorView(message: error) {
                Task { await load() }
            }
            .accessibilityFocused($focusContent)
        } else if vm.packages.isEmpty {
            EmptyModuleView(
                title: "Aucun paquet installé",
                systemImage: "shippingbox",
                description: "Installez des paquets depuis DSM pour les gérer ici."
            )
            .accessibilityFocused($focusContent)
        } else {
            List(vm.packages) { package in
                row(for: package)
            }
            .accessibilityFocused($focusContent)
        }
    }

    private func row(for package: PackageInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(package.displayName).fontWeight(.medium)
                if let version = package.version, !version.isEmpty {
                    Text("Version \(version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let newVersion = vm.updateVersion(for: package) {
                    Text("Mise à jour disponible : \(newVersion)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(package.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control(for: package)
        }
        .contextMenu {
            if package.canUninstall {
                Button("Désinstaller…", role: .destructive) { pendingUninstall = package }
            }
        }
    }

    /// Boutons d'action à droite : Démarrer/Arrêter (si pilotable) et Désinstaller (si permis).
    @ViewBuilder
    private func control(for package: PackageInfo) -> some View {
        let isBusy = vm.busy.contains(package.id)
        HStack(spacing: 8) {
            if package.canStartStop {
                if package.isRunning {
                    Button("Arrêter") { setRunning(package, running: false) }
                        .disabled(isBusy)
                        .accessibilityLabel("Arrêter \(package.displayName)")
                } else {
                    Button("Démarrer") { setRunning(package, running: true) }
                        .disabled(isBusy)
                        .accessibilityLabel("Démarrer \(package.displayName)")
                }
            }
            if package.canUninstall {
                Button(role: .destructive) {
                    pendingUninstall = package
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isBusy)
                .accessibilityLabel("Désinstaller \(package.displayName)")
            }
        }
    }

    private func setRunning(_ package: PackageInfo, running: Bool) {
        Task {
            let msg = await vm.setRunning(package, running: running)
            VoiceOver.announce(msg, priority: .high)
        }
    }

    private func requestUninstall(_ package: PackageInfo) {
        Task {
            let msg = await vm.uninstall(package)
            VoiceOver.announce(msg, priority: .high)
        }
    }

    private func load() async {
        focusContent = true
        await vm.load()
        guard !Task.isCancelled else { return }
        focusContent = true
        VoiceOver.announce(vm.summary)
    }

    /// Avertissement honnête affiché avant la désinstallation.
    private func uninstallWarning(for package: PackageInfo) -> String {
        var text = String(localized: "« \(package.displayName) » sera désinstallé. Les données stockées dans des dossiers partagés (photos, bases de données…) peuvent être conservées selon le paquet ; pour les supprimer, utilisez le module Partages. Vous pourrez réinstaller le paquet depuis DSM.")
        if package.hasUninstallOptions {
            text += " " + String(localized: "Ce paquet propose des options de désinstallation dans DSM (conserver ou supprimer les données) qui ne sont pas disponibles ici : les réglages par défaut seront appliqués.")
        }
        return text
    }
}
