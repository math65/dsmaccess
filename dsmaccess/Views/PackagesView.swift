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
    @State private var pendingUpdate: PackageInfo?
    @State private var showSettings = false
    @AccessibilityFocusState private var focusTitle: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _vm = State(initialValue: PackagesViewModel(session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .padding(28)
        .frame(maxWidth: 560, alignment: .leading)
        .task {
            focusTitle = true
            await vm.load()
            AccessibilityNotification.Announcement(vm.summary).post()
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
        .confirmationDialog(
            "Mettre à jour ce paquet ?",
            isPresented: Binding(
                get: { pendingUpdate != nil },
                set: { if !$0 { pendingUpdate = nil } }
            ),
            presenting: pendingUpdate
        ) { package in
            Button("Mettre à jour \(package.displayName)") {
                requestUpdate(package)
            }
            Button("Annuler", role: .cancel) { }
        } message: { package in
            Text(updateWarning(for: package))
        }
        .sheet(isPresented: $showSettings) {
            PackageSettingsSheet(session: session)
        }
    }

    private var header: some View {
        HStack {
            Text("Centre de paquets")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Label("Réglages du Centre de paquets", systemImage: "gearshape")
            }
            .accessibilityLabel("Réglages du Centre de paquets")
            .accessibilityHint("Ouvre les réglages du Centre de paquets")
            Button {
                Task { await vm.load(); AccessibilityNotification.Announcement(vm.summary).post() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .accessibilityHint("Recharge la liste des paquets")
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.packages.isEmpty {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Chargement…").foregroundStyle(.secondary)
            }
        } else if let error = vm.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Text(error).foregroundStyle(.red)
                Button("Réessayer") {
                    Task { await vm.load(); AccessibilityNotification.Announcement(vm.summary).post() }
                }
            }
        } else if vm.packages.isEmpty {
            Text("Aucun paquet installé").foregroundStyle(.secondary)
        } else {
            List(vm.packages) { package in
                row(for: package)
            }
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
            if let newVersion = vm.updateVersion(for: package) {
                Button("Mettre à jour") { pendingUpdate = package }
                    .disabled(isBusy)
                    .accessibilityLabel("Mettre à jour \(package.displayName) vers la version \(newVersion)")
            }
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

    private func requestUpdate(_ package: PackageInfo) {
        Task {
            // Étapes simples : on annonce le début (l'opération dure ~1-2 min), puis le résultat.
            VoiceOver.announce(String(localized: "Mise à jour de \(package.displayName) en cours…"), priority: .high)
            let msg = await vm.applyUpdate(package)
            VoiceOver.announce(msg, priority: .high)
        }
    }

    /// Avertissement honnête affiché avant la mise à jour.
    private func updateWarning(for package: PackageInfo) -> String {
        let version = vm.updateVersion(for: package) ?? ""
        return String(localized: "« \(package.displayName) » va être mis à jour vers la version \(version). Le paquet est téléchargé puis installé, ce qui peut prendre une à deux minutes, et il sera redémarré. Si la mise à jour nécessite un redémarrage du NAS, effectuez-le depuis DSM.")
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
