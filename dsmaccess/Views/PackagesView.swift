//
//  PackagesView.swift
//  dsmaccess
//  Gestion des paquets installés sur DSM.

import SwiftUI

struct PackagesView: View {
    @State private var vm: PackagesViewModel
    @State private var pendingUninstall: PackageInfo?
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var filter = PackageFilter.all
    @AccessibilityFocusState private var focusContent: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _vm = State(initialValue: PackagesViewModel(session: session))
    }

    var body: some View {
        content
        .searchable(text: $searchText, prompt: "Rechercher des paquets")
        .toolbar {
            ToolbarItem {
                Picker("Filtrer les paquets", selection: $filter) {
                    ForEach(PackageFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .help("Filtrer les paquets")
            }

            ToolbarItem {
                Button {
                    showSettings = true
                } label: {
                    Label("Réglages du Centre de paquets", systemImage: "gearshape")
                }
                .help("Réglages du Centre de paquets")
            }

            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser les paquets")
            }
        }
        .task {
            await load(restoresInitialFocus: true)
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
            .help(String(localized: "Désinstaller \(package.displayName)"))
            Button("Annuler", role: .cancel) { }
                .help("Conserver ce paquet")
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
        } else if filteredPackages.isEmpty {
            ContentUnavailableView(
                "Aucun paquet correspondant",
                systemImage: "shippingbox",
                description: Text("Modifiez la recherche ou le filtre.")
            )
        } else {
            List(filteredPackages) { package in
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
            if package.canStartStop {
                Button(package.isRunning ? "Arrêter" : "Démarrer") {
                    setRunning(package, running: !package.isRunning)
                }
                .disabled(vm.busy.contains(package.id))
                .help(package.isRunning ? "Arrêter ce paquet" : "Démarrer ce paquet")
            }
            if package.canUninstall {
                if package.canStartStop { Divider() }
                Button("Désinstaller…", role: .destructive) { pendingUninstall = package }
                    .disabled(vm.busy.contains(package.id))
                    .help("Désinstaller ce paquet")
            }
        }
    }

    private var filteredPackages: [PackageInfo] {
        vm.packages.filter { package in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .running: package.isRunning
            case .stopped: !package.isRunning
            case .updates: vm.updateVersion(for: package) != nil
            }
            let matchesSearch = searchText.isEmpty
                || package.displayName.localizedStandardContains(searchText)
                || package.pkgId.localizedStandardContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    @ViewBuilder
    private func control(for package: PackageInfo) -> some View {
        let isBusy = vm.busy.contains(package.id)
        HStack(spacing: 8) {
            if package.canStartStop {
                if package.isRunning {
                    Button("Arrêter") { setRunning(package, running: false) }
                        .disabled(isBusy)
                        .accessibilityLabel("Arrêter \(package.displayName)")
                        .help(String(localized: "Arrêter \(package.displayName)"))
                } else {
                    Button("Démarrer") { setRunning(package, running: true) }
                        .disabled(isBusy)
                        .accessibilityLabel("Démarrer \(package.displayName)")
                        .help(String(localized: "Démarrer \(package.displayName)"))
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
                .help(String(localized: "Désinstaller \(package.displayName)"))
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

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "Chargement des paquets…"),
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
            category: vm.errorMessage == nil ? .result : .error
        )
    }

    private func uninstallWarning(for package: PackageInfo) -> String {
        var text = String(localized: "« \(package.displayName) » sera désinstallé. Les données stockées dans des dossiers partagés (photos, bases de données…) peuvent être conservées selon le paquet ; pour les supprimer, utilisez le module Partages. Vous pourrez réinstaller le paquet depuis DSM.")
        if package.hasUninstallOptions {
            text += " " + String(localized: "Ce paquet propose des options de désinstallation dans DSM (conserver ou supprimer les données) qui ne sont pas disponibles ici : les réglages par défaut seront appliqués.")
        }
        return text
    }
}

private enum PackageFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case stopped
    case updates

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: "Tous"
        case .running: "En cours"
        case .stopped: "Arrêtés"
        case .updates: "Mises à jour"
        }
    }
}
