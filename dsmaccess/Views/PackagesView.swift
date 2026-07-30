//
//  PackagesView.swift
//  dsmaccess
//  Management of the packages installed on DSM.

import SwiftUI
import UniformTypeIdentifiers

struct PackagesView: View {
    @State private var vm: PackagesViewModel
    @State private var pendingUninstall: PackageInfo?
    @State private var pendingUpdate: PackageInfo?
    @State private var pendingRepair: PackageInfo?
    @State private var pendingManualPackage: URL?
    @State private var pendingCatalogAction: CatalogActionRequest?
    @State private var confirmsUpdateAll = false
    @State private var detailsPackage: PackageInfo?
    @State private var showSettings = false
    @State private var showPackageSources = false
    @State private var showPackageImporter = false
    @State private var section = PackageCenterSection.installed
    @State private var searchText = ""
    @State private var filter = PackageFilter.all
    @State private var catalogFilter = CatalogFilter.all
    @State private var refreshTask: Task<Void, Never>?
    @State private var operationTask: Task<Void, Never>?
    @State private var operationError: String?
    @AccessibilityFocusState private var focusContent: Bool
    @AccessibilityFocusState private var focusOperationError: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _vm = State(initialValue: PackagesViewModel(session: session))
    }

    var body: some View {
        presentationContent
    }

    private var baseContent: some View {
        VStack(spacing: 0) {
            // In the content rather than the toolbar: VoiceOver must meet the
            // Installed/Catalog choice in reading order, like a real picker.
            sectionPicker
            statusBanners
            content
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .toolbar {
            packageToolbar
        }
        .task {
            await load(restoresInitialFocus: true)
        }
        .onChange(of: section) { _, newSection in
            searchText = ""
            focusContent = true
            VoiceOver.announce(newSection.announcement, category: .navigation)
        }
        .onDisappear {
            refreshTask?.cancel()
            operationTask?.cancel()
        }
    }

    private var confirmationContent: some View {
        baseContent
        .confirmationDialog(
            "packages.uninstall.confirm",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            presenting: pendingUninstall
        ) { package in
            Button(String(localized: "packages.uninstall.action", defaultValue: "Uninstall \(package.displayName)"), role: .destructive) {
                requestUninstall(package)
            }
            .help(String(localized: "packages.uninstall.action", defaultValue: "Uninstall \(package.displayName)"))
            Button("common.button.cancel", role: .cancel) { }
                .help("packages.uninstall.confirm.cancel")
        } message: { package in
            Text(uninstallWarning(for: package))
        }
        .confirmationDialog(
            "packages.update.confirm",
            isPresented: Binding(
                get: { pendingUpdate != nil },
                set: { if !$0 { pendingUpdate = nil } }
            ),
            presenting: pendingUpdate
        ) { package in
            Button(String(localized: "packages.update.action", defaultValue: "Update \(package.displayName)")) {
                requestUpdate(package)
            }
            .help(String(localized: "packages.update.action", defaultValue: "Update \(package.displayName)"))
            Button("common.button.cancel", role: .cancel) { }
                .help("packages.update.confirm.cancel")
        } message: { package in
            Text(updateWarning(for: package))
        }
        .confirmationDialog(
            "packages.repair.confirm",
            isPresented: Binding(
                get: { pendingRepair != nil },
                set: { if !$0 { pendingRepair = nil } }
            ),
            presenting: pendingRepair
        ) { package in
            Button(String(localized: "packages.repair.action", defaultValue: "Repair \(package.displayName)")) {
                requestRepair(package)
            }
            Button("common.button.cancel", role: .cancel) { }
        } message: { package in
            Text(repairWarning(for: package))
        }
        .confirmationDialog(
            "packages.install_spk.confirm",
            isPresented: Binding(
                get: { pendingManualPackage != nil },
                set: { if !$0 { pendingManualPackage = nil } }
            ),
            presenting: pendingManualPackage
        ) { fileURL in
            Button(String(localized: "packages.install.action", defaultValue: "Install \(fileURL.lastPathComponent)")) {
                requestManualInstallation(fileURL)
            }
            Button("common.button.cancel", role: .cancel) { }
        } message: { fileURL in
            Text(manualInstallationWarning(for: fileURL))
        }
        .confirmationDialog(
            catalogConfirmationTitle,
            isPresented: Binding(
                get: { pendingCatalogAction != nil },
                set: { if !$0 { pendingCatalogAction = nil } }
            ),
            presenting: pendingCatalogAction
        ) { request in
            Button(catalogConfirmButtonTitle(for: request)) {
                requestCatalogOperation(request)
            }
            Button("common.button.cancel", role: .cancel) { }
        } message: { request in
            Text(catalogConfirmationMessage(for: request))
        }
        .confirmationDialog(
            "packages.update_all.confirm",
            isPresented: $confirmsUpdateAll
        ) {
            Button("packages.update_all.button") { requestUpdateAll() }
            Button("common.button.cancel", role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "packages.update_all.confirm.description",
                    defaultValue: "\(vm.updateCount) packages will be updated one at a time. Each download and installation will be started only once."
                )
            )
        }
    }

    private var presentationContent: some View {
        confirmationContent
        .sheet(isPresented: $showSettings) {
            PackageSettingsSheet(
                session: session,
                canManagePackageSources: vm.capabilities?.canManagePackageSources == true
            )
        }
        .sheet(isPresented: $showPackageSources) {
            PackageSourcesSheet(session: session)
        }
        .sheet(item: $detailsPackage) { package in
            PackageDetailsSheet(vm: vm, package: package)
        }
        .fileImporter(
            isPresented: $showPackageImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handlePackageSelection(result)
        }
    }

    private var sectionPicker: some View {
        Picker("common.module.package_center", selection: $section) {
            ForEach(PackageCenterSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(operationTask != nil || refreshTask != nil)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var packageToolbar: some ToolbarContent {
        ToolbarItem {
            if section == .installed {
                Picker("packages.filter.label", selection: $filter) {
                    ForEach(PackageFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .help("packages.filter.label")
            } else {
                Picker("common.button.show", selection: $catalogFilter) {
                    ForEach(CatalogFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .help("packages.filter.label")
            }
        }

        if section == .installed {
            ToolbarItem {
                Button {
                    confirmsUpdateAll = true
                } label: {
                    Label("packages.update_all.button", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(vm.updateCount == 0 || !vm.canApplyUpdates || operationTask != nil)
                .help("packages.update_all.hint")
            }
        }

        ToolbarItem {
            Menu {
                Button("packages.manual_install.button", systemImage: "shippingbox.and.arrow.forward") {
                    showPackageImporter = true
                }
                .disabled(
                    vm.capabilities?.canInstallManualPackages != true || operationTask != nil
                )
                Button("packages.menu.sources", systemImage: "link") {
                    showPackageSources = true
                }
                .disabled(
                    vm.capabilities?.canManagePackageSources != true || operationTask != nil
                )
                Divider()
                Button("packages.menu.settings", systemImage: "gearshape") {
                    showSettings = true
                }
                .disabled(
                    vm.capabilities?.canManageSettings != true || operationTask != nil
                )
            } label: {
                Label("packages.more_actions.label", systemImage: "ellipsis.circle")
            }
            .help("packages.more_actions.hint")
        }

        ToolbarItem {
            Button {
                startRefresh()
            } label: {
                Label("common.button.refresh", systemImage: "arrow.clockwise")
            }
            .disabled(vm.isLoading || refreshTask != nil || operationTask != nil)
            .help(refreshHelp)
        }
    }

    private var searchPrompt: LocalizedStringKey {
        section == .installed ? "packages.search.field" : "packages.catalog.search.field"
    }

    private var refreshHelp: String {
        section == .installed
            ? String(localized: "packages.refresh.button")
            : String(localized: "packages.catalog.refresh.hint")
    }

    @ViewBuilder
    private var statusBanners: some View {
        if let operationStatus = vm.operationStatusText {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(operationStatus)
                Spacer()
                Button("packages.monitoring.stop.button") { stopTrackingOperation() }
                    .help("packages.monitoring.stop.hint")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary)
            .accessibilityElement(children: .contain)
        }
        if section == .installed, let catalogError = vm.catalogErrorMessage {
            Label(
                String(localized: "packages.catalog.unavailable.error", defaultValue: "Catalog unavailable: \(catalogError)"),
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .foregroundStyle(.readableSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
        }
        if let operationError {
            HStack {
                Label(operationError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.readableRed)
                    .accessibilityFocused($focusOperationError)
                Spacer()
                Button("common.button.dismiss_error") { self.operationError = nil }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .installed:
            installedContent
        case .catalog:
            PackageCatalogView(
                vm: vm,
                searchText: searchText,
                filter: catalogFilter,
                operationsDisabled: operationTask != nil,
                retry: startRefresh,
                requestAction: { pendingCatalogAction = $0 }
            )
            .accessibilityFocused($focusContent)
        }
    }

    @ViewBuilder
    private var installedContent: some View {
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
                title: "packages.empty.title",
                systemImage: "shippingbox",
                description: "packages.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else if filteredPackages.isEmpty {
            ContentUnavailableView(
                "common.empty.matching_packages",
                systemImage: "shippingbox",
                description: Text("packages.search.empty.description")
            )
        } else {
            List(filteredPackages) { package in
                row(for: package)
            }
            .accessibilityLabel("packages.installed.table.label")
            .accessibilityFocused($focusContent)
        }
    }

    private func row(for package: PackageInfo) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(package.displayName).fontWeight(.medium)
                Text(package.pkgId)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                if let version = package.version, !version.isEmpty {
                    Text(String(localized: "packages.version.label", defaultValue: "Version \(version)"))
                        .font(.caption)
                        .foregroundStyle(.readableSecondary)
                }
                if let newVersion = vm.updateVersion(for: package) {
                    Text(String(localized: "packages.update.available.label", defaultValue: "Update available: \(newVersion)"))
                        .font(.caption)
                        .foregroundStyle(.readableOrange)
                }
                Text(package.statusText)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                if package.requiresAttention {
                    Text("common.status.repair_required")
                        .font(.caption)
                        .foregroundStyle(.readableRed)
                } else if package.hasUninstallOptions {
                    Text("packages.uninstall.assistant_required.title")
                        .font(.caption)
                        .foregroundStyle(.readableSecondary)
                }
            }
            Spacer()
            Button("common.button.details", systemImage: "info.circle") { detailsPackage = package }
                .labelStyle(.iconOnly)
                .help("packages.details.button")
            control(for: package)
        }
        .contextMenu {
            if vm.canRepair(package) {
                Button("packages.repair.menu") { pendingRepair = package }
                    .disabled(vm.busy.contains(package.id) || operationTask != nil)
                Divider()
            }
            if let version = vm.updateVersion(for: package) {
                Button("packages.update.menu") { pendingUpdate = package }
                    .disabled(
                        vm.busy.contains(package.id)
                            || !vm.canApplyUpdates
                            || operationTask != nil
                    )
                    .help(
                        String(
                            localized: "common.action.update_package",
                            defaultValue: "Update \(package.displayName) to version \(version)"
                        )
                    )
                if package.canStartStop || package.canUninstall {
                    Divider()
                }
            }
            if package.canStartStop, vm.capabilities?.canControlPackages == true {
                Button(package.isRunning ? "common.button.stop" : "common.button.start") {
                    setRunning(package, running: !package.isRunning)
                }
                .disabled(vm.busy.contains(package.id) || operationTask != nil)
                .help(package.isRunning ? "packages.stop.hint" : "packages.start.hint")
            }
            if vm.canSafelyUninstall(package) {
                if package.canStartStop { Divider() }
                Button("packages.uninstall.menu", role: .destructive) { pendingUninstall = package }
                    .disabled(vm.busy.contains(package.id) || operationTask != nil)
                    .help("packages.uninstall.hint")
            }
        }
    }

    private var filteredPackages: [PackageInfo] {
        vm.packages.filter { package in
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .running: package.isRunning
            case .stopped: package.isStopped
            case .updates: vm.updateVersion(for: package) != nil
            case .attention: package.requiresAttention
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
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "common.status.operation_in_progress", defaultValue: "Operation in progress for \(package.displayName)"))
            }
            if let version = vm.updateVersion(for: package) {
                Button("common.button.update") { pendingUpdate = package }
                    .disabled(isBusy || !vm.canApplyUpdates || operationTask != nil)
                    .accessibilityLabel(
                        String(
                            localized: "common.action.update_package",
                            defaultValue: "Update \(package.displayName) to version \(version)"
                        )
                    )
                    .help(
                        String(
                            localized: "common.action.update_package",
                            defaultValue: "Update \(package.displayName) to version \(version)"
                        )
                    )
            }
            if vm.canRepair(package) {
                Button("packages.repair.button") { pendingRepair = package }
                    .disabled(isBusy || operationTask != nil)
                    .accessibilityLabel(String(localized: "packages.repair.action", defaultValue: "Repair \(package.displayName)"))
                    .help(String(localized: "packages.repair.action", defaultValue: "Repair \(package.displayName)"))
            }
            if package.canStartStop, vm.capabilities?.canControlPackages == true {
                if package.isRunning {
                    Button("common.button.stop") { setRunning(package, running: false) }
                        .disabled(isBusy || operationTask != nil)
                        .accessibilityLabel(String(localized: "packages.stop.action", defaultValue: "Stop \(package.displayName)"))
                        .help(String(localized: "packages.stop.action", defaultValue: "Stop \(package.displayName)"))
                } else {
                    Button("common.button.start") { setRunning(package, running: true) }
                        .disabled(isBusy || operationTask != nil)
                        .accessibilityLabel(String(localized: "packages.start.action", defaultValue: "Start \(package.displayName)"))
                        .help(String(localized: "packages.start.action", defaultValue: "Start \(package.displayName)"))
                }
            }
            if vm.canSafelyUninstall(package) {
                Button(role: .destructive) {
                    pendingUninstall = package
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isBusy || operationTask != nil)
                .accessibilityLabel(String(localized: "packages.uninstall.action", defaultValue: "Uninstall \(package.displayName)"))
                .help(String(localized: "packages.uninstall.action", defaultValue: "Uninstall \(package.displayName)"))
            }
        }
    }

    private func startRefresh() {
        guard refreshTask == nil else { return }
        let refreshesCatalog = section == .catalog
        refreshTask = Task {
            defer { refreshTask = nil }
            await load(
                forceCatalogRefresh: refreshesCatalog,
                announcesResult: !refreshesCatalog
            )
            guard refreshesCatalog, !Task.isCancelled else { return }
            if let error = vm.errorMessage ?? vm.catalogErrorMessage {
                focusContent = true
                VoiceOver.announce(error, category: .error, priority: .high)
            } else {
                focusContent = true
                VoiceOver.announce(
                    String(localized: "packages.catalog.refreshed.announcement", defaultValue: "Catalog refreshed: \(vm.catalog.count) packages"),
                    category: .result
                )
            }
        }
    }

    private func setRunning(_ package: PackageInfo, running: Bool) {
        let announcement = running
            ? String(localized: "packages.start.progress", defaultValue: "Starting \(package.displayName)…")
            : String(localized: "packages.stop.progress", defaultValue: "Stopping \(package.displayName)…")
        startOperation(announcement: announcement) {
            await vm.setRunning(package, running: running)
        }
    }

    private func requestUninstall(_ package: PackageInfo) {
        startOperation(
            announcement: String(localized: "packages.uninstall.progress", defaultValue: "Uninstalling \(package.displayName)…")
        ) {
            await vm.uninstall(package)
        }
    }

    private func requestUpdate(_ package: PackageInfo) {
        startOperation(
            announcement: String(localized: "packages.update.progress", defaultValue: "Updating \(package.displayName)…")
        ) {
            await vm.applyUpdate(package)
        }
    }

    private func requestRepair(_ package: PackageInfo) {
        startOperation(
            announcement: String(localized: "packages.repair.progress", defaultValue: "Repairing \(package.displayName)…")
        ) {
            await vm.repair(package)
        }
    }

    private var catalogConfirmationTitle: String {
        guard let pendingCatalogAction else {
            return String(localized: "packages.install.confirm")
        }
        return pendingCatalogAction.installedPackage == nil
            ? String(localized: "packages.install.confirm")
            : String(localized: "packages.update.confirm")
    }

    private func catalogConfirmButtonTitle(for request: CatalogActionRequest) -> String {
        if let installedPackage = request.installedPackage {
            return String(localized: "packages.update.action", defaultValue: "Update \(installedPackage.displayName)")
        }
        return String(localized: "packages.install.action", defaultValue: "Install \(request.item.packageID)")
    }

    private func catalogConfirmationMessage(for request: CatalogActionRequest) -> String {
        if let installedPackage = request.installedPackage {
            return String(
                localized: "packages.update.confirm.description",
                defaultValue: "“\(installedPackage.displayName)” will be updated to version \(request.item.version). The package will be downloaded, installed, and restarted."
            )
        }
        return String(
            localized: "packages.install.confirm.description",
            defaultValue: "“\(request.item.packageID)” version \(request.item.version) will be downloaded from the official catalog, installed, and started if supported by the package."
        )
    }

    private func requestCatalogOperation(_ request: CatalogActionRequest) {
        if let installedPackage = request.installedPackage {
            startOperation(
                announcement: String(
                    localized: "packages.update.progress",
                    defaultValue: "Updating \(installedPackage.displayName)…"
                )
            ) {
                await vm.applyUpdate(installedPackage)
            }
        } else {
            startOperation(
                announcement: String(
                    localized: "packages.install.progress",
                    defaultValue: "Installing \(request.item.packageID)…"
                )
            ) {
                await vm.install(request.item)
            }
        }
    }

    private func requestManualInstallation(_ fileURL: URL) {
        startOperation(
            announcement: String(
                localized: "packages.install.progress",
                defaultValue: "Installing \(fileURL.lastPathComponent)…"
            )
        ) {
            await vm.installManualPackage(at: fileURL)
        }
    }

    private func requestUpdateAll() {
        startOperation(
            announcement: String(localized: "packages.update_all.progress")
        ) {
            await vm.applyAllUpdates()
        }
    }

    private func startOperation(
        announcement: String,
        operation: @escaping @MainActor () async -> DSMOperationOutcome
    ) {
        guard operationTask == nil else { return }
        operationError = nil
        VoiceOver.announce(announcement, category: .progress, priority: .high)
        operationTask = Task {
            let outcome = await operation()
            if case .failure(let message) = outcome {
                operationError = message
                focusOperationError = true
            }
            if case .cancelled = outcome {
                operationTask = nil
                return
            }
            VoiceOver.announce(outcome, priority: .high)
            operationTask = nil
        }
    }

    private func stopTrackingOperation() {
        operationTask?.cancel()
        VoiceOver.announce(
            String(
                localized: "packages.monitoring.stop.description"
            ),
            category: .progress,
            priority: .high
        )
    }

    private func load(
        restoresInitialFocus: Bool = false,
        forceCatalogRefresh: Bool = false,
        announcesResult: Bool = true
    ) async {
        VoiceOver.announce(
            String(localized: "packages.loading.progress"),
            category: .progress,
            priority: .low
        )
        await vm.load(forceCatalogRefresh: forceCatalogRefresh)
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        }
        guard announcesResult else { return }
        VoiceOver.announce(
            vm.summary,
            category: vm.errorMessage == nil && vm.catalogErrorMessage == nil ? .result : .error
        )
    }

    private func uninstallWarning(for package: PackageInfo) -> String {
        var text = String(localized: "packages.uninstall.confirm.description", defaultValue: "“\(package.displayName)” will be uninstalled. Data stored in shared folders (photos, databases…) may be kept depending on the package; to delete it, use the Shares module. You can reinstall the package from DSM.")
        if package.hasUninstallOptions {
            text += " " + String(localized: "packages.uninstall.assistant_required.description")
        }
        return text
    }

    private func updateWarning(for package: PackageInfo) -> String {
        let version = vm.updateVersion(for: package) ?? ""
        return String(
            localized: "packages.update.confirm.restart_description",
            defaultValue: "“\(package.displayName)” will be updated to version \(version). The package will be downloaded, installed, and restarted. This may take several minutes. If DSM requires a NAS restart, you will need to do it from DSM."
        )
    }

    private func repairWarning(for package: PackageInfo) -> String {
        let catalogVersion = vm.catalogItem(for: package)?.version ?? ""
        if vm.update(for: package) != nil {
            return String(
                localized: "packages.repair.confirm.update_description",
                defaultValue: "“\(package.displayName)” will be repaired using version \(catalogVersion) from the official catalog. This will also update the package and may restart it."
            )
        }
        return String(
            localized: "packages.repair.confirm.reinstall_description",
            defaultValue: "“\(package.displayName)” will be reinstalled from the official catalog to replace its damaged files. The package may be restarted."
        )
    }

    private func manualInstallationWarning(for fileURL: URL) -> String {
        String(
            localized: "packages.install_spk.confirm.description",
            defaultValue: "The “\(fileURL.lastPathComponent)” file will be uploaded to the NAS and installed. A package can run software with access to NAS resources. Continue only if you trust its source."
        )
    }

    private func handlePackageSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first,
                  fileURL.pathExtension.caseInsensitiveCompare("spk") == .orderedSame else {
                presentOperationError(
                    String(localized: "packages.manual_install.file_picker.hint")
                )
                return
            }
            pendingManualPackage = fileURL
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            presentOperationError(
                String(localized: "packages.manual_install.file_open.error", defaultValue: "Unable to open the package file: \(error.localizedDescription)")
            )
        }
    }

    private func presentOperationError(_ message: String) {
        operationError = message
        focusOperationError = true
        VoiceOver.announce(message, category: .error, priority: .high)
    }
}

private enum PackageCenterSection: CaseIterable, Hashable, Identifiable {
    case installed
    case catalog

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .installed: "common.filter.installed"
        case .catalog: "common.label.official_catalog"
        }
    }

    var announcement: String {
        switch self {
        case .installed: String(localized: "common.filter.installed")
        case .catalog: String(localized: "common.label.official_catalog")
        }
    }
}

private enum PackageFilter: String, CaseIterable, Identifiable {
    case all
    case running
    case stopped
    case updates
    case attention

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: "common.filter.all"
        case .running: "common.status.in_progress"
        case .stopped: "packages.filter.stopped"
        case .updates: "common.label.updates"
        case .attention: "packages.filter.needs_repair"
        }
    }
}
