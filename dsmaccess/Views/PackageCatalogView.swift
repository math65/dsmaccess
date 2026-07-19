//
//  PackageCatalogView.swift
//  dsmaccess
//
//  Catalogue officiel et détails fondés sur les métadonnées vérifiées du NAS.
//

import SwiftUI

struct PackageCatalogView: View {
    @Bindable var vm: PackagesViewModel
    let refresh: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var filter = CatalogFilter.all
    @State private var isRefreshing = false
    @State private var refreshTask: Task<Void, Never>?
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusStatus: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button("Fermer", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 760, height: 560)
        .onAppear {
            focusHeading = true
            VoiceOver.announce("Catalogue officiel", category: .navigation)
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private var header: some View {
        HStack {
            Text("Catalogue officiel")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)
            Spacer()
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Actualisation du catalogue…")
            }
            Button("Fermer", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isRefreshing)
        }
        .padding()
    }

    private var controls: some View {
        HStack(spacing: 14) {
            TextField("Rechercher dans le catalogue", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
            Picker("Afficher", selection: $filter) {
                ForEach(CatalogFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .frame(maxWidth: 230)
            Spacer()
            Button("Actualiser", systemImage: "arrow.clockwise") {
                startRefresh()
            }
            .disabled(isRefreshing)
            .help("Forcer l’actualisation du catalogue sur le NAS")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let error = vm.errorMessage ?? vm.catalogErrorMessage {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Réessayer") { startRefresh() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if visibleCatalog.isEmpty {
            ContentUnavailableView(
                "Aucun paquet correspondant",
                systemImage: "shippingbox",
                description: Text("Modifiez la recherche ou le filtre du catalogue.")
            )
            .accessibilityFocused($focusStatus)
        } else {
            List(visibleCatalog) { item in
                catalogRow(item)
            }
            .accessibilityLabel("Catalogue officiel du Centre de paquets")
        }
    }

    private var visibleCatalog: [PackageUpdate] {
        vm.catalog.filter { item in
            let installed = vm.installedPackage(for: item)
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .notInstalled: installed == nil
            case .installed: installed != nil
            case .updates: installed.map { vm.update(for: $0) != nil } == true
            }
            let matchesSearch = searchText.isEmpty
                || item.packageID.localizedStandardContains(searchText)
                || item.version.localizedStandardContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    private func catalogRow(_ item: PackageUpdate) -> some View {
        let installedPackage = vm.installedPackage(for: item)
        return PackageCatalogRow(
            item: item,
            installedPackage: installedPackage,
            updateAvailable: installedPackage.map { vm.update(for: $0) != nil } == true
        )
    }

    private func refreshCatalog() async {
        isRefreshing = true
        defer { isRefreshing = false }
        VoiceOver.announce(
            String(localized: "Actualisation du catalogue…"),
            category: .progress,
            priority: .low
        )
        await refresh()
        guard !Task.isCancelled else { return }
        if let error = vm.errorMessage ?? vm.catalogErrorMessage {
            focusStatus = true
            VoiceOver.announce(error, category: .error, priority: .high)
        } else {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "Catalogue actualisé : \(vm.catalog.count) paquets"),
                category: .result
            )
        }
    }

    private func startRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            await refreshCatalog()
            refreshTask = nil
        }
    }
}

private struct PackageCatalogRow: View {
    let item: PackageUpdate
    let installedPackage: PackageInfo?
    let updateAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.packageID)
                    .fontWeight(.medium)
                if item.isBeta {
                    Text("Bêta")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formattedFileSize)
                    .foregroundStyle(.secondary)
            }
            Text("Version du catalogue : \(item.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            installationStatus
        }
    }

    @ViewBuilder
    private var installationStatus: some View {
        if let installed = installedPackage {
            Text(String(localized: "Version installée : \(installedVersion(for: installed))"))
                .font(.caption)
                .foregroundStyle(.secondary)
            if updateAvailable {
                Text("Mise à jour disponible")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("À jour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Non installé")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("L’installation depuis le catalogue n’est pas disponible dans DSM Access sur ce NAS. Installez ce paquet depuis le Centre de paquets DSM.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var formattedFileSize: String {
        item.fileSize.formatted(.byteCount(style: .file))
    }

    private func installedVersion(for package: PackageInfo) -> String {
        package.version ?? String(localized: "Inconnue")
    }
}

private enum CatalogFilter: String, CaseIterable, Identifiable {
    case all
    case notInstalled
    case installed
    case updates

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: "Tous"
        case .notInstalled: "Non installés"
        case .installed: "Installés"
        case .updates: "Mises à jour"
        }
    }
}

struct PackageDetailsSheet: View {
    @Bindable var vm: PackagesViewModel
    let package: PackageInfo

    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusHeading: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Détails du paquet")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)
            Divider()
            Form {
                installedSection
                actionsSection
                catalogSection
                apiSection
                unavailableMetadataSection
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Fermer", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 620, height: 650)
        .onAppear {
            focusHeading = true
            VoiceOver.announce("Détails du paquet", category: .navigation)
        }
    }

    private var installedSection: some View {
        Section("Paquet installé") {
            LabeledContent("Nom", value: package.displayName)
            LabeledContent("Identifiant", value: package.pkgId)
            if let version = package.version {
                LabeledContent("Version installée", value: version)
            }
            LabeledContent("État", value: package.statusText)
            if let installType = package.additional?.installType {
                LabeledContent("Type d’installation", value: installType)
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions disponibles sur ce NAS") {
            LabeledContent(
                "Démarrage et arrêt",
                value: yesNo(
                    package.canStartStop
                        && vm.capabilities?.canControlPackages == true
                )
            )
            LabeledContent(
                "Désinstallation directe",
                value: yesNo(vm.canSafelyUninstall(package))
            )
            if package.hasUninstallOptions {
                Text("Ce paquet exige l’assistant de désinstallation de DSM afin de traiter ses données sans choix implicite.")
                    .foregroundStyle(.secondary)
            }
            if package.requiresAttention {
                Text("DSM signale que ce paquet nécessite une réparation. La réparation n’est pas disponible dans DSM Access sur ce NAS ; utilisez le Centre de paquets DSM.")
                    .foregroundStyle(.red)
            }
        }
    }

    private var catalogSection: some View {
        Section("Catalogue officiel") {
            if let catalogItem {
                LabeledContent("Source", value: "Synology")
                LabeledContent("Version du catalogue", value: catalogItem.version)
                LabeledContent(
                    "Taille",
                    value: catalogItem.fileSize.formatted(.byteCount(style: .file))
                )
                LabeledContent("Version bêta", value: yesNo(catalogItem.isBeta))
            } else {
                Text("Ce paquet n’est pas présent dans le catalogue officiel actuellement chargé.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var apiSection: some View {
        Section("API disponibles") {
            ForEach(availableAPIs, id: \.name) { api in
                LabeledContent(api.name) {
                    Text(api.version, format: .number.grouping(.never))
                }
            }
        }
    }

    private var unavailableMetadataSection: some View {
        Section {
            Text("Ce NAS ne fournit pas à DSM Access les dépendances, licences, sources tierces ni pages de configuration de ce paquet.")
                .foregroundStyle(.secondary)
        }
    }

    private var catalogItem: PackageUpdate? {
        vm.catalog.first {
            $0.packageID.caseInsensitiveCompare(package.pkgId) == .orderedSame
        }
    }

    private var availableAPIs: [(name: String, version: Int)] {
        (vm.capabilities?.maximumVersions ?? [:])
            .map { (name: $0.key, version: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Oui") : String(localized: "Non")
    }
}
