//
//  PackagesView.swift
//  dsmaccess
//  Gestion des paquets installés sur DSM.

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
            .help(String(localized: "Mettre à jour \(package.displayName)"))
            Button("Annuler", role: .cancel) { }
                .help("Ne pas mettre à jour ce paquet")
        } message: { package in
            Text(updateWarning(for: package))
        }
        .confirmationDialog(
            "Réparer ce paquet ?",
            isPresented: Binding(
                get: { pendingRepair != nil },
                set: { if !$0 { pendingRepair = nil } }
            ),
            presenting: pendingRepair
        ) { package in
            Button("Réparer \(package.displayName)") {
                requestRepair(package)
            }
            Button("Annuler", role: .cancel) { }
        } message: { package in
            Text(repairWarning(for: package))
        }
        .confirmationDialog(
            "Installer ce fichier SPK ?",
            isPresented: Binding(
                get: { pendingManualPackage != nil },
                set: { if !$0 { pendingManualPackage = nil } }
            ),
            presenting: pendingManualPackage
        ) { fileURL in
            Button("Installer \(fileURL.lastPathComponent)") {
                requestManualInstallation(fileURL)
            }
            Button("Annuler", role: .cancel) { }
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
            Button("Annuler", role: .cancel) { }
        } message: { request in
            Text(catalogConfirmationMessage(for: request))
        }
        .confirmationDialog(
            "Mettre à jour tous les paquets ?",
            isPresented: $confirmsUpdateAll
        ) {
            Button("Tout mettre à jour") { requestUpdateAll() }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "\(vm.updateCount) paquets seront mis à jour l’un après l’autre. Chaque téléchargement et chaque installation est lancé une seule fois."
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

    @ToolbarContentBuilder
    private var packageToolbar: some ToolbarContent {
        ToolbarItem {
            Picker("Centre de paquets", selection: $section) {
                ForEach(PackageCenterSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Centre de paquets")
            .disabled(operationTask != nil || refreshTask != nil)
        }

        ToolbarItem {
            if section == .installed {
                Picker("Filtrer les paquets", selection: $filter) {
                    ForEach(PackageFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .help("Filtrer les paquets")
            } else {
                Picker("Afficher", selection: $catalogFilter) {
                    ForEach(CatalogFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .help("Filtrer les paquets")
            }
        }

        if section == .installed {
            ToolbarItem {
                Button {
                    confirmsUpdateAll = true
                } label: {
                    Label("Tout mettre à jour", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(vm.updateCount == 0 || !vm.canApplyUpdates || operationTask != nil)
                .help("Mettre à jour tous les paquets compatibles")
            }
        }

        ToolbarItem {
            Menu {
                Button("Installation manuelle…", systemImage: "shippingbox.and.arrow.forward") {
                    showPackageImporter = true
                }
                .disabled(
                    vm.capabilities?.canInstallManualPackages != true || operationTask != nil
                )
                Button("Sources de paquets…", systemImage: "link") {
                    showPackageSources = true
                }
                .disabled(
                    vm.capabilities?.canManagePackageSources != true || operationTask != nil
                )
                Divider()
                Button("Réglages du Centre de paquets…", systemImage: "gearshape") {
                    showSettings = true
                }
                .disabled(
                    vm.capabilities?.canManageSettings != true || operationTask != nil
                )
            } label: {
                Label("Plus d’actions", systemImage: "ellipsis.circle")
            }
            .help("Installation manuelle, sources et réglages du Centre de paquets")
        }

        ToolbarItem {
            Button {
                startRefresh()
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .disabled(vm.isLoading || refreshTask != nil || operationTask != nil)
            .help(refreshHelp)
        }
    }

    private var searchPrompt: LocalizedStringKey {
        section == .installed ? "Rechercher des paquets" : "Rechercher dans le catalogue"
    }

    private var refreshHelp: String {
        section == .installed
            ? String(localized: "Actualiser les paquets")
            : String(localized: "Forcer l’actualisation du catalogue sur le NAS")
    }

    @ViewBuilder
    private var statusBanners: some View {
        if let operationStatus = vm.operationStatusText {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(operationStatus)
                Spacer()
                Button("Arrêter le suivi") { stopTrackingOperation() }
                    .help("Arrêter le suivi dans l’app ; l’installation peut continuer sur le NAS")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary)
            .accessibilityElement(children: .contain)
        }
        if section == .installed, let catalogError = vm.catalogErrorMessage {
            Label(
                String(localized: "Catalogue indisponible : \(catalogError)"),
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
        }
        if let operationError {
            HStack {
                Label(operationError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityFocused($focusOperationError)
                Spacer()
                Button("Fermer l’erreur") { self.operationError = nil }
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
                title: "Aucun paquet installé",
                systemImage: "shippingbox",
                description: "Installez un paquet depuis le catalogue officiel ou un fichier SPK."
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
                Text(package.pkgId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                if package.requiresAttention {
                    Text("Réparation requise")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if package.hasUninstallOptions {
                    Text("Assistant DSM requis pour la désinstallation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Détails", systemImage: "info.circle") { detailsPackage = package }
                .labelStyle(.iconOnly)
                .help("Afficher les détails de ce paquet")
            control(for: package)
        }
        .contextMenu {
            if vm.canRepair(package) {
                Button("Réparer…") { pendingRepair = package }
                    .disabled(vm.busy.contains(package.id) || operationTask != nil)
                Divider()
            }
            if let version = vm.updateVersion(for: package) {
                Button("Mettre à jour…") { pendingUpdate = package }
                    .disabled(
                        vm.busy.contains(package.id)
                            || !vm.canApplyUpdates
                            || operationTask != nil
                    )
                    .help(
                        String(
                            localized: "Mettre à jour \(package.displayName) vers la version \(version)"
                        )
                    )
                if package.canStartStop || package.canUninstall {
                    Divider()
                }
            }
            if package.canStartStop, vm.capabilities?.canControlPackages == true {
                Button(package.isRunning ? "Arrêter" : "Démarrer") {
                    setRunning(package, running: !package.isRunning)
                }
                .disabled(vm.busy.contains(package.id) || operationTask != nil)
                .help(package.isRunning ? "Arrêter ce paquet" : "Démarrer ce paquet")
            }
            if vm.canSafelyUninstall(package) {
                if package.canStartStop { Divider() }
                Button("Désinstaller…", role: .destructive) { pendingUninstall = package }
                    .disabled(vm.busy.contains(package.id) || operationTask != nil)
                    .help("Désinstaller ce paquet")
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
                    .accessibilityLabel("Opération en cours pour \(package.displayName)")
            }
            if let version = vm.updateVersion(for: package) {
                Button("Mettre à jour") { pendingUpdate = package }
                    .disabled(isBusy || !vm.canApplyUpdates || operationTask != nil)
                    .accessibilityLabel(
                        "Mettre à jour \(package.displayName) vers la version \(version)"
                    )
                    .help(
                        String(
                            localized: "Mettre à jour \(package.displayName) vers la version \(version)"
                        )
                    )
            }
            if vm.canRepair(package) {
                Button("Réparer") { pendingRepair = package }
                    .disabled(isBusy || operationTask != nil)
                    .accessibilityLabel("Réparer \(package.displayName)")
                    .help(String(localized: "Réparer \(package.displayName)"))
            }
            if package.canStartStop, vm.capabilities?.canControlPackages == true {
                if package.isRunning {
                    Button("Arrêter") { setRunning(package, running: false) }
                        .disabled(isBusy || operationTask != nil)
                        .accessibilityLabel("Arrêter \(package.displayName)")
                        .help(String(localized: "Arrêter \(package.displayName)"))
                } else {
                    Button("Démarrer") { setRunning(package, running: true) }
                        .disabled(isBusy || operationTask != nil)
                        .accessibilityLabel("Démarrer \(package.displayName)")
                        .help(String(localized: "Démarrer \(package.displayName)"))
                }
            }
            if vm.canSafelyUninstall(package) {
                Button(role: .destructive) {
                    pendingUninstall = package
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isBusy || operationTask != nil)
                .accessibilityLabel("Désinstaller \(package.displayName)")
                .help(String(localized: "Désinstaller \(package.displayName)"))
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
                    String(localized: "Catalogue actualisé : \(vm.catalog.count) paquets"),
                    category: .result
                )
            }
        }
    }

    private func setRunning(_ package: PackageInfo, running: Bool) {
        let announcement = running
            ? String(localized: "Démarrage de \(package.displayName) en cours…")
            : String(localized: "Arrêt de \(package.displayName) en cours…")
        startOperation(announcement: announcement) {
            await vm.setRunning(package, running: running)
        }
    }

    private func requestUninstall(_ package: PackageInfo) {
        startOperation(
            announcement: String(localized: "Désinstallation de \(package.displayName) en cours…")
        ) {
            await vm.uninstall(package)
        }
    }

    private func requestUpdate(_ package: PackageInfo) {
        startOperation(
            announcement: String(localized: "Mise à jour de \(package.displayName) en cours…")
        ) {
            await vm.applyUpdate(package)
        }
    }

    private func requestRepair(_ package: PackageInfo) {
        startOperation(
            announcement: String(localized: "Réparation de \(package.displayName) en cours…")
        ) {
            await vm.repair(package)
        }
    }

    private var catalogConfirmationTitle: String {
        guard let pendingCatalogAction else {
            return String(localized: "Installer ce paquet ?")
        }
        return pendingCatalogAction.installedPackage == nil
            ? String(localized: "Installer ce paquet ?")
            : String(localized: "Mettre à jour ce paquet ?")
    }

    private func catalogConfirmButtonTitle(for request: CatalogActionRequest) -> String {
        if let installedPackage = request.installedPackage {
            return String(localized: "Mettre à jour \(installedPackage.displayName)")
        }
        return String(localized: "Installer \(request.item.packageID)")
    }

    private func catalogConfirmationMessage(for request: CatalogActionRequest) -> String {
        if let installedPackage = request.installedPackage {
            return String(
                localized: "« \(installedPackage.displayName) » sera mis à jour vers la version \(request.item.version). Le paquet sera téléchargé, installé puis redémarré."
            )
        }
        return String(
            localized: "« \(request.item.packageID) » version \(request.item.version) sera téléchargé depuis le catalogue officiel, installé puis démarré si le paquet le permet."
        )
    }

    private func requestCatalogOperation(_ request: CatalogActionRequest) {
        if let installedPackage = request.installedPackage {
            startOperation(
                announcement: String(
                    localized: "Mise à jour de \(installedPackage.displayName) en cours…"
                )
            ) {
                await vm.applyUpdate(installedPackage)
            }
        } else {
            startOperation(
                announcement: String(
                    localized: "Installation de \(request.item.packageID) en cours…"
                )
            ) {
                await vm.install(request.item)
            }
        }
    }

    private func requestManualInstallation(_ fileURL: URL) {
        startOperation(
            announcement: String(
                localized: "Installation de \(fileURL.lastPathComponent) en cours…"
            )
        ) {
            await vm.installManualPackage(at: fileURL)
        }
    }

    private func requestUpdateAll() {
        startOperation(
            announcement: String(localized: "Mise à jour de tous les paquets en cours…")
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
                localized: "Suivi arrêté dans l’app. L’opération déjà envoyée au NAS peut continuer dans DSM."
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
            String(localized: "Chargement des paquets…"),
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
        var text = String(localized: "« \(package.displayName) » sera désinstallé. Les données stockées dans des dossiers partagés (photos, bases de données…) peuvent être conservées selon le paquet ; pour les supprimer, utilisez le module Partages. Vous pourrez réinstaller le paquet depuis DSM.")
        if package.hasUninstallOptions {
            text += " " + String(localized: "Ce paquet propose un assistant de désinstallation dans DSM. DSM Access ne lancera pas sa désinstallation sans cet assistant.")
        }
        return text
    }

    private func updateWarning(for package: PackageInfo) -> String {
        let version = vm.updateVersion(for: package) ?? ""
        return String(
            localized: "« \(package.displayName) » sera mis à jour vers la version \(version). Le paquet sera téléchargé, installé puis redémarré. L’opération peut prendre plusieurs minutes. Si DSM exige un redémarrage du NAS, vous devrez l’effectuer depuis DSM."
        )
    }

    private func repairWarning(for package: PackageInfo) -> String {
        let catalogVersion = vm.catalogItem(for: package)?.version ?? ""
        if vm.update(for: package) != nil {
            return String(
                localized: "« \(package.displayName) » sera réparé avec la version \(catalogVersion) du catalogue officiel. Cette opération mettra aussi le paquet à jour et pourra le redémarrer."
            )
        }
        return String(
            localized: "« \(package.displayName) » sera réinstallé depuis le catalogue officiel afin de remplacer ses fichiers endommagés. Le paquet pourra être redémarré."
        )
    }

    private func manualInstallationWarning(for fileURL: URL) -> String {
        String(
            localized: "Le fichier « \(fileURL.lastPathComponent) » sera envoyé au NAS puis installé. Un paquet peut exécuter du logiciel avec accès aux ressources du NAS. Continuez uniquement si vous faites confiance à sa provenance."
        )
    }

    private func handlePackageSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first,
                  fileURL.pathExtension.caseInsensitiveCompare("spk") == .orderedSame else {
                presentOperationError(
                    String(localized: "Sélectionnez un fichier de paquet portant l’extension .spk.")
                )
                return
            }
            pendingManualPackage = fileURL
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            presentOperationError(
                String(localized: "Impossible d’ouvrir le fichier de paquet : \(error.localizedDescription)")
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
        case .installed: "Installés"
        case .catalog: "Catalogue officiel"
        }
    }

    var announcement: String {
        switch self {
        case .installed: String(localized: "Installés")
        case .catalog: String(localized: "Catalogue officiel")
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
        case .all: "Tous"
        case .running: "En cours"
        case .stopped: "Arrêtés"
        case .updates: "Mises à jour"
        case .attention: "À réparer"
        }
    }
}
