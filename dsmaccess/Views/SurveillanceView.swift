//
//  SurveillanceView.swift
//  dsmaccess
//
//  État, activation et aperçu des caméras Surveillance Station.
//

import AppKit
import SwiftUI

struct SurveillanceView: View {
    @State private var viewModel: SurveillanceViewModel
    @State private var selection: Set<String> = []
    @State private var searchText = ""
    @State private var autoRefresh = true
    @State private var showInspector = false
    @AccessibilityFocusState private var contentFocused: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: SurveillanceViewModel(session: session))
    }

    var body: some View {
        content
            .navigationTitle("Surveillance Station")
            .searchable(text: $searchText, prompt: "Rechercher une caméra")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load() }
            .task(id: autoRefresh) { await refreshPeriodically() }
            .inspector(isPresented: $showInspector) { inspector }
            .onChange(of: selection) {
                guard showInspector, let selectedCamera else { return }
                Task { await loadSnapshot(selectedCamera) }
            }
            .onChange(of: viewModel.cameras) {
                selection.formIntersection(Set(viewModel.cameras.map(\.id)))
                if selection.count != 1 { showInspector = false }
            }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.cameras.isEmpty {
            ModuleLoadingView("Chargement des caméras…")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredCameras.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "Aucune caméra" : "Aucun résultat",
                systemImage: "video",
                description: searchText.isEmpty
                    ? "Ajoutez une caméra dans Surveillance Station pour la gérer ici."
                    : "Modifiez votre recherche et réessayez."
            )
            .accessibilityFocused($contentFocused)
        } else {
            List(filteredCameras, selection: $selection) { camera in
                cameraRow(camera)
                    .tag(camera.id)
                    .contextMenu { cameraActions(camera) }
            }
            .accessibilityLabel("Caméras")
            .accessibilityFocused($contentFocused)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await setSelected(enabled: true) }
            } label: {
                Label("Activer", systemImage: "video.badge.checkmark")
            }
            .disabled(!selectionCanEnable || selectionIsBusy)
            .help("Activer les caméras sélectionnées")
        }

        ToolbarItem {
            Button {
                Task { await setSelected(enabled: false) }
            } label: {
                Label("Désactiver", systemImage: "video.slash")
            }
            .disabled(!selectionCanDisable || selectionIsBusy)
            .help("Désactiver les caméras sélectionnées")
        }

        ToolbarItem {
            Button {
                showInspector.toggle()
                if showInspector, let selectedCamera {
                    Task { await loadSnapshot(selectedCamera) }
                }
            } label: {
                Label("Instantané et informations", systemImage: "photo")
            }
            .disabled(selectedCamera == nil)
            .help(showInspector ? "Masquer l’instantané" : "Afficher l’instantané et les informations")
        }

        ToolbarItem {
            Menu {
                Toggle("Actualisation automatique", isOn: $autoRefresh)
                    .help("Actualiser automatiquement les caméras")
            } label: {
                Label("Options d’actualisation", systemImage: "ellipsis.circle")
            }
            .help("Options d’actualisation")
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            .help("Actualiser les caméras")
        }
    }

    private func cameraRow(_ camera: SurveillanceCamera) -> some View {
        HStack(spacing: 12) {
            Image(systemName: camera.isAvailable ? "video.fill" : "video.slash.fill")
                .foregroundStyle(camera.isAvailable ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(camera.name).fontWeight(.medium)
                HStack(spacing: 8) {
                    Text(statusText(camera.status))
                    if let address = camera.address { Text(address) }
                    if let resolution = camera.resolution { Text(resolution) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.busyIDs.contains(camera.id) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Opération en cours pour \(camera.name)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cameraAccessibilityLabel(camera))
        .accessibilityActions {
            if !viewModel.busyIDs.contains(camera.id) {
                Button(camera.enabled ? "Désactiver" : "Activer") {
                    Task { await set(enabled: !camera.enabled, ids: [camera.id]) }
                }
                .help(camera.enabled ? "Désactiver cette caméra" : "Activer cette caméra")
            }
            Button("Charger l’instantané") {
                selection = [camera.id]
                showInspector = true
                Task { await loadSnapshot(camera) }
            }
            .help("Charger l’instantané de cette caméra")
        }
    }

    @ViewBuilder
    private func cameraActions(_ camera: SurveillanceCamera) -> some View {
        Button(camera.enabled ? "Désactiver" : "Activer") {
            Task { await set(enabled: !camera.enabled, ids: [camera.id]) }
        }
        .help(camera.enabled ? "Désactiver cette caméra" : "Activer cette caméra")
        Divider()
        Button("Instantané et informations") {
            selection = [camera.id]
            showInspector = true
            Task { await loadSnapshot(camera) }
        }
        .help("Afficher l’instantané et les informations de cette caméra")
    }

    @ViewBuilder
    private var inspector: some View {
        if let camera = selectedCamera {
            VStack(spacing: 0) {
                snapshotView(camera)
                    .frame(minHeight: 180, idealHeight: 240)
                Divider()
                Form {
                    Section("Caméra") {
                        LabeledContent("Nom", value: camera.name)
                        LabeledContent("État", value: statusText(camera.status))
                        LabeledContent("Activée", value: camera.enabled ? "Oui" : "Non")
                        if let address = addressText(camera) { LabeledContent("Adresse", value: address) }
                        if let vendor = camera.vendor { LabeledContent("Fabricant", value: vendor) }
                        if let model = camera.model { LabeledContent("Modèle", value: model) }
                    }
                    Section("Vidéo") {
                        if let resolution = camera.resolution { LabeledContent("Résolution", value: resolution) }
                        if let fps = camera.framesPerSecond {
                            LabeledContent("Fréquence d’images", value: String(localized: "\(fps) images par seconde"))
                        }
                        if let codec = codecText(camera.videoCodec) { LabeledContent("Codec", value: codec) }
                    }
                }
                .formStyle(.grouped)
            }
            .inspectorColumnWidth(min: 320, ideal: 380, max: 520)
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await loadSnapshot(camera) }
                    } label: {
                        Label("Actualiser l’instantané", systemImage: "camera.rotate")
                    }
                    .help("Actualiser l’instantané")
                }
            }
            .accessibilityLabel("Instantané et informations de \(camera.name)")
        } else {
            EmptyModuleView(
                title: "Aucune sélection",
                systemImage: "video",
                description: "Sélectionnez une caméra pour afficher son instantané."
            )
        }
    }

    @ViewBuilder
    private func snapshotView(_ camera: SurveillanceCamera) -> some View {
        if viewModel.isLoadingSnapshot && viewModel.snapshotCameraID == camera.id {
            ModuleLoadingView("Chargement de l’instantané…")
        } else if let message = viewModel.snapshotErrorMessage, viewModel.snapshotCameraID == camera.id {
            ModuleErrorView(message: message) { Task { await loadSnapshot(camera) } }
        } else if viewModel.snapshotCameraID == camera.id,
                  let data = viewModel.snapshotData,
                  let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Instantané actuel de \(camera.name)")
                .accessibilityAddTraits(.isImage)
                .padding(8)
        } else {
            EmptyModuleView(
                title: "Aucun instantané",
                systemImage: "photo",
                description: "Actualisez pour demander une image à la caméra."
            )
        }
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.summary)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    private var filteredCameras: [SurveillanceCamera] {
        guard !searchText.isEmpty else { return viewModel.cameras }
        return viewModel.cameras.filter {
            $0.name.localizedStandardContains(searchText)
                || ($0.address?.localizedStandardContains(searchText) == true)
                || ($0.vendor?.localizedStandardContains(searchText) == true)
                || ($0.model?.localizedStandardContains(searchText) == true)
        }
    }

    private var selectedCameras: [SurveillanceCamera] {
        viewModel.cameras.filter { selection.contains($0.id) }
    }

    private var selectedCamera: SurveillanceCamera? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return viewModel.cameras.first { $0.id == id }
    }

    private var selectionCanEnable: Bool { selectedCameras.contains { !$0.enabled } }
    private var selectionCanDisable: Bool { selectedCameras.contains { $0.enabled } }
    private var selectionIsBusy: Bool { !viewModel.busyIDs.isDisjoint(with: selection) }

    private func load() async {
        VoiceOver.announce(
            String(localized: "Chargement de Surveillance Station…"),
            category: .progress,
            priority: .low
        )
        await viewModel.load()
        guard !Task.isCancelled else { return }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .result : .error
        )
    }

    private func refreshPeriodically() async {
        guard autoRefresh else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, autoRefresh else { return }
            await viewModel.load(silently: true)
        }
    }

    private func setSelected(enabled: Bool) async {
        let ids = Set(selectedCameras.filter { $0.enabled != enabled }.map(\.id))
        await set(enabled: enabled, ids: ids)
    }

    private func set(enabled: Bool, ids: Set<String>) async {
        VoiceOver.announce(await viewModel.setEnabled(enabled, ids: ids), priority: .high)
    }

    private func loadSnapshot(_ camera: SurveillanceCamera) async {
        await viewModel.loadSnapshot(for: camera)
        if let message = viewModel.snapshotErrorMessage {
            VoiceOver.announce(message, priority: .high)
        } else if viewModel.snapshotData != nil {
            VoiceOver.announce(String(localized: "Instantané chargé pour \(camera.name)"))
        }
    }

    private func cameraAccessibilityLabel(_ camera: SurveillanceCamera) -> String {
        var parts = [camera.name, statusText(camera.status)]
        if let address = camera.address { parts.append(address) }
        if let resolution = camera.resolution { parts.append(resolution) }
        return parts.formatted(.list(type: .and))
    }

    private func addressText(_ camera: SurveillanceCamera) -> String? {
        guard let address = camera.address else { return nil }
        if let port = camera.port { return "\(address):\(port)" }
        return address
    }

    private func codecText(_ codec: Int?) -> String? {
        switch codec {
        case 1: "MJPEG"
        case 2: "MPEG-4"
        case 3: "H.264"
        case 5: "MXPEG"
        case 6: "H.265"
        case 7: "H.264+"
        default: nil
        }
    }

    private func statusText(_ status: Int) -> String {
        switch status {
        case 1: String(localized: "Normale")
        case 2: String(localized: "Supprimée")
        case 3: String(localized: "Déconnectée")
        case 4: String(localized: "Indisponible")
        case 5: String(localized: "Prête")
        case 6: String(localized: "Inaccessible")
        case 7: String(localized: "Désactivée")
        case 8: String(localized: "Non reconnue")
        case 9: String(localized: "Configuration")
        case 10: String(localized: "Serveur déconnecté")
        case 11: String(localized: "Migration")
        case 13: String(localized: "Stockage retiré")
        case 14: String(localized: "Arrêt en cours")
        case 15: String(localized: "Historique de connexion indisponible")
        case 16: String(localized: "Non autorisée")
        case 17: String(localized: "Erreur RTSP")
        case 18: String(localized: "Aucune vidéo")
        default: String(localized: "État inconnu")
        }
    }
}
