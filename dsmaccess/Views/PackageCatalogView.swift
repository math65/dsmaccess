//
//  PackageCatalogView.swift
//  dsmaccess
//
//  Catalogue officiel et détails fondés sur les métadonnées vérifiées du NAS.
//

import SwiftUI

struct PackageCatalogView: View {
    @Bindable var vm: PackagesViewModel
    let searchText: String
    let filter: CatalogFilter
    let operationsDisabled: Bool
    let retry: () -> Void
    let requestAction: (CatalogActionRequest) -> Void

    var body: some View {
        if vm.isLoading && vm.catalog.isEmpty {
            ModuleLoadingView()
        } else if let error = vm.errorMessage ?? vm.catalogErrorMessage {
            ModuleErrorView(message: error, retry: retry)
        } else if vm.capabilities != nil && !vm.canBrowseCatalog {
            // DSM n'expose pas SYNO.Core.Package.Server aux comptes non administrateurs :
            // sans cet état explicite, l'onglet paraît vide sans raison.
            ContentUnavailableView(
                "Catalogue non disponible",
                systemImage: "shippingbox",
                description: Text(
                    "Ce NAS ne donne pas accès au catalogue officiel avec ce compte. Connectez-vous avec un compte administrateur pour parcourir le catalogue Synology."
                )
            )
        } else if visibleCatalog.isEmpty {
            ContentUnavailableView(
                "Aucun paquet correspondant",
                systemImage: "shippingbox",
                description: Text("Modifiez la recherche ou le filtre du catalogue.")
            )
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
            updateAvailable: installedPackage.map { vm.update(for: $0) != nil } == true,
            action: action(for: item, installedPackage: installedPackage),
            isDisabled: operationsDisabled || vm.busy.contains(item.packageID),
            requestAction: {
                requestAction(
                    CatalogActionRequest(
                        item: item,
                        installedPackage: installedPackage
                    )
                )
            }
        )
    }

    private func action(
        for item: PackageUpdate,
        installedPackage: PackageInfo?
    ) -> CatalogRowAction? {
        if let installedPackage {
            return vm.update(for: installedPackage) != nil && vm.canApplyUpdates ? .update : nil
        }
        return vm.canInstall(item) ? .install : nil
    }
}

private struct PackageCatalogRow: View {
    let item: PackageUpdate
    let installedPackage: PackageInfo?
    let updateAvailable: Bool
    let action: CatalogRowAction?
    let isDisabled: Bool
    let requestAction: () -> Void

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
                if let action {
                    Button(action.title, action: requestAction)
                        .disabled(isDisabled)
                        .accessibilityLabel(action.accessibilityLabel(for: item))
                }
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
            if let unavailableInstallDescription {
                Text(unavailableInstallDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableInstallDescription: String? {
        if item.requirements.requiresInteractiveInstaller {
            return String(
                localized: "Une licence ou un assistant de configuration DSM est requis pour ce paquet."
            )
        }
        if action == nil {
            return String(
                localized: "L’installation depuis le catalogue n’est pas disponible sur ce NAS."
            )
        }
        return nil
    }

    private var formattedFileSize: String {
        item.fileSize.formatted(.byteCount(style: .file))
    }

    private func installedVersion(for package: PackageInfo) -> String {
        package.version ?? String(localized: "Inconnue")
    }
}

struct CatalogActionRequest {
    let item: PackageUpdate
    let installedPackage: PackageInfo?
}

private enum CatalogRowAction: Equatable {
    case install
    case update

    var title: String {
        switch self {
        case .install: String(localized: "Installer")
        case .update: String(localized: "Mettre à jour")
        }
    }

    func accessibilityLabel(for item: PackageUpdate) -> String {
        switch self {
        case .install:
            String(localized: "Installer \(item.packageID) version \(item.version)")
        case .update:
            String(localized: "Mettre à jour \(item.packageID) vers la version \(item.version)")
        }
    }
}

enum CatalogFilter: String, CaseIterable, Identifiable {
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
                LabeledContent("Réparation", value: yesNo(vm.canRepair(package)))
                Text(repairAvailabilityDescription)
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

    private var repairAvailabilityDescription: String {
        vm.canRepair(package)
            ? String(
                localized: "Ce paquet peut être réparé depuis la liste des paquets installés."
            )
            : String(
                localized: "Aucun paquet officiel compatible n’est disponible pour une réparation directe. Utilisez le Centre de paquets DSM."
            )
    }

    private func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Oui") : String(localized: "Non")
    }
}
