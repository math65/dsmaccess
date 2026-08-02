//
//  PackageCatalogView.swift
//  dsmaccess
//
//  Official catalog and details based on the NAS's verified metadata.
//

import SwiftUI

struct PackageCatalogView: View {
    @Bindable var vm: PackagesViewModel
    let searchText: String
    let filter: CatalogFilter
    let operationsDisabled: Bool
    let retry: () -> Void
    let requestAction: (CatalogActionRequest) -> Void

    @State private var selection = Set<PackageUpdate.ID>()
    @State private var order = [KeyPathComparator(\PackageUpdate.packageID, order: .forward)]

    var body: some View {
        if vm.isLoading && vm.catalog.isEmpty {
            ModuleLoadingView()
        } else if let error = vm.errorMessage ?? vm.catalogErrorMessage {
            ModuleErrorView(message: error, retry: retry)
        } else if vm.capabilities != nil && !vm.canBrowseCatalog {
            // DSM does not expose SYNO.Core.Package.Server to non-administrator accounts:
            // without this explicit state, the tab looks empty for no reason.
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
            Table(
                visibleCatalog.sorted(using: order),
                selection: $selection,
                sortOrder: $order
            ) {
                TableColumn("common.column.identifier", value: \.packageID) { item in
                    Text(item.packageID)
                }
                TableColumn("common.column.version", value: \.version) { item in
                    Text(item.version)
                }
                TableColumn("common.column.size", value: \.fileSize) { item in
                    Text(item.fileSize.formatted(.byteCount(style: .file)))
                }
                TableColumn("packages.column.beta", value: \.sortableBeta) { item in
                    Text(item.betaDescription)
                }
                // Not sortable: what is installed comes from the view model, not from the
                // catalog entry, so there is no key path to sort on.
                TableColumn("packages.column.installed_version") { item in
                    Text(installedVersionText(for: item))
                }
                TableColumn("common.column.state") { item in
                    Text(installationStateText(for: item))
                        .foregroundStyle(
                            updateAvailable(for: item) ? .readableOrange : .readableSecondary
                        )
                }
            }
            .accessibilityLabel("packages.catalog.source.official")
            .contextMenu(forSelectionType: PackageUpdate.ID.self) { ids in
                if let item = visibleCatalog.first(where: { ids.contains($0.id) }) {
                    catalogActions(for: item)
                }
            }
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

    private func updateAvailable(for item: PackageUpdate) -> Bool {
        vm.installedPackage(for: item).map { vm.update(for: $0) != nil } == true
    }

    private func installedVersionText(for item: PackageUpdate) -> String {
        guard let installed = vm.installedPackage(for: item) else {
            return String(localized: "packages.status.not_installed")
        }
        return installed.version ?? String(localized: "packages.detail.source.unknown")
    }

    /// One column carries the whole install story: up to date, an update waiting, or the
    /// reason the app cannot install it here.
    private func installationStateText(for item: PackageUpdate) -> String {
        if vm.installedPackage(for: item) != nil {
            return updateAvailable(for: item)
                ? String(localized: "packages.status.update_available")
                : String(localized: "packages.status.up_to_date")
        }
        if item.requirements.requiresInteractiveInstaller {
            return String(localized: "packages.install.requires_dsm.description")
        }
        if action(for: item, installedPackage: nil) == nil {
            return String(localized: "common.error.catalog_install_unavailable")
        }
        return String(localized: "packages.status.not_installed")
    }

    @ViewBuilder
    private func catalogActions(for item: PackageUpdate) -> some View {
        let installedPackage = vm.installedPackage(for: item)
        if let action = action(for: item, installedPackage: installedPackage) {
            Button(action.title) {
                requestAction(
                    CatalogActionRequest(item: item, installedPackage: installedPackage)
                )
            }
            .disabled(operationsDisabled || vm.busy.contains(item.packageID))
        }
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
            .accessibilityLabel("packages.detail.information.label")
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
            VoiceOver.announce(String(localized: "packages.details.title"), category: .navigation)
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
