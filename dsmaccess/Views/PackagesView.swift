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
    @AccessibilityFocusState private var focusTitle: Bool

    init(session: SessionStore) {
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
    }

    private var header: some View {
        HStack {
            Text("Centre de paquets")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)
            Spacer()
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
    }

    /// Bouton Démarrer/Arrêter, seulement pour les paquets pilotables.
    @ViewBuilder
    private func control(for package: PackageInfo) -> some View {
        let isBusy = vm.busy.contains(package.id)
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
        // Sinon : pas de bouton (l'état reste lisible dans le bloc de gauche).
    }

    private func setRunning(_ package: PackageInfo, running: Bool) {
        Task {
            let msg = await vm.setRunning(package, running: running)
            VoiceOver.announce(msg, priority: .high)
        }
    }
}
