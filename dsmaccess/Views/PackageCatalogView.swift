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
                "packages.catalog.unavailable.title",
                systemImage: "shippingbox",
                description: Text(
                    "packages.catalog.unavailable.description"
                )
            )
        } else if visibleCatalog.isEmpty {
            ContentUnavailableView(
                "common.empty.matching_packages",
                systemImage: "shippingbox",
                description: Text("packages.catalog.empty.description")
            )
        } else {
            List(visibleCatalog) { item in
                catalogRow(item)
            }
            .accessibilityLabel("packages.catalog.source.official")
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
                    Text("packages.filter.beta")
                        .font(.caption)
                        .foregroundStyle(.readableSecondary)
                }
                Spacer()
                Text(formattedFileSize)
                    .foregroundStyle(.readableSecondary)
                if let action {
                    Button(action.title, action: requestAction)
                        .disabled(isDisabled)
                        .accessibilityLabel(action.accessibilityLabel(for: item))
                }
            }
            Text(String(localized: "packages.catalog.version.value", defaultValue: "Catalog version: \(item.version)"))
                .font(.caption)
                .foregroundStyle(.readableSecondary)
            installationStatus
        }
    }

    @ViewBuilder
    private var installationStatus: some View {
        if let installed = installedPackage {
            Text(String(localized: "common.status.installed_version", defaultValue: "Installed version: \(installedVersion(for: installed))"))
                .font(.caption)
                .foregroundStyle(.readableSecondary)
            if updateAvailable {
                Text("packages.status.update_available")
                    .font(.caption)
                    .foregroundStyle(.readableOrange)
            } else {
                Text("packages.status.up_to_date")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
            }
        } else {
            Text("packages.status.not_installed")
                .font(.caption)
                .foregroundStyle(.readableSecondary)
            if let unavailableInstallDescription {
                Text(unavailableInstallDescription)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
            }
        }
    }

    private var unavailableInstallDescription: String? {
        if item.requirements.requiresInteractiveInstaller {
            return String(
                localized: "packages.install.requires_dsm.description"
            )
        }
        if action == nil {
            return String(
                localized: "common.error.catalog_install_unavailable"
            )
        }
        return nil
    }

    private var formattedFileSize: String {
        item.fileSize.formatted(.byteCount(style: .file))
    }

    private func installedVersion(for package: PackageInfo) -> String {
        package.version ?? String(localized: "packages.detail.source.unknown")
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
        case .install: String(localized: "packages.install.button")
        case .update: String(localized: "common.button.update")
        }
    }

    func accessibilityLabel(for item: PackageUpdate) -> String {
        switch self {
        case .install:
            String(localized: "packages.install.action.with_version", defaultValue: "Install \(item.packageID) version \(item.version)")
        case .update:
            String(localized: "common.action.update_package", defaultValue: "Update \(item.packageID) to version \(item.version)")
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
        case .all: "common.filter.all"
        case .notInstalled: "packages.filter.not_installed"
        case .installed: "common.filter.installed"
        case .updates: "common.label.updates"
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
            Text("packages.detail.title")
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
                Button("common.button.close", role: .cancel) { dismiss() }
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
        Section("packages.status.installed") {
            LabeledContent("common.column.name", value: package.displayName)
            LabeledContent("common.column.identifier", value: package.pkgId)
            if let version = package.version {
                LabeledContent("common.label.installed_version", value: version)
            }
            LabeledContent("common.column.state", value: package.statusText)
            if let installType = package.additional?.installType {
                LabeledContent("packages.detail.installation_type", value: installType)
            }
        }
    }

    private var actionsSection: some View {
        Section("packages.detail.actions.section") {
            LabeledContent(
                "packages.detail.action.start_stop",
                value: yesNo(
                    package.canStartStop
                        && vm.capabilities?.canControlPackages == true
                )
            )
            LabeledContent(
                "packages.detail.action.direct_uninstall",
                value: yesNo(vm.canSafelyUninstall(package))
            )
            if package.hasUninstallOptions {
                Text("packages.uninstall.requires_dsm.description")
                    .foregroundStyle(.readableSecondary)
            }
            if package.requiresAttention {
                LabeledContent("packages.detail.action.repair", value: yesNo(vm.canRepair(package)))
                Text(repairAvailabilityDescription)
                .foregroundStyle(.readableRed)
            }
        }
    }

    private var catalogSection: some View {
        Section("common.label.official_catalog") {
            if let catalogItem {
                LabeledContent("packages.detail.source", value: "Synology")
                LabeledContent("packages.catalog.version.label", value: catalogItem.version)
                LabeledContent(
                    "common.column.size",
                    value: catalogItem.fileSize.formatted(.byteCount(style: .file))
                )
                LabeledContent("packages.detail.beta_version", value: yesNo(catalogItem.isBeta))
            } else {
                Text("packages.catalog.missing_package.description")
                    .foregroundStyle(.readableSecondary)
            }
        }
    }

    private var apiSection: some View {
        Section("packages.detail.available_apis") {
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
                localized: "packages.repair.from_installed.description"
            )
            : String(
                localized: "packages.repair.unavailable.description"
            )
    }

    private func yesNo(_ value: Bool) -> String {
        value ? String(localized: "common.answer.yes") : String(localized: "common.answer.no")
    }
}
