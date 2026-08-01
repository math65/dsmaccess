//
//  SurveillanceView.swift
//  dsmaccess
//
//  Status, enabling and preview of Surveillance Station cameras.
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
            .searchable(text: $searchText, prompt: "surveillance.camera.search.label")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { statusBar }
            .task { await load(restoresInitialFocus: true) }
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
            ModuleLoadingView("surveillance.camera.loading")
                .accessibilityFocused($contentFocused)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($contentFocused)
        } else if filteredCameras.isEmpty {
            EmptyModuleView(
                title: searchText.isEmpty ? "surveillance.camera.empty" : "common.empty.results",
                systemImage: "video",
                description: searchText.isEmpty
                    ? "surveillance.empty.description"
                    : "common.empty.results.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            List(filteredCameras, selection: $selection) { camera in
                cameraRow(camera)
                    .tag(camera.id)
                    .contextMenu { cameraActions(camera) }
            }
            .accessibilityLabel("surveillance.cameras.title")
            .accessibilityFocused($contentFocused)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await setSelected(enabled: true) }
            } label: {
                Label("common.button.enable", systemImage: "video.badge.checkmark")
            }
            .disabled(!selectionCanEnable || selectionIsBusy)
            .help("surveillance.camera.enable_selected.action")
        }

        ToolbarItem {
            Button {
                Task { await setSelected(enabled: false) }
            } label: {
                Label("common.button.disable", systemImage: "video.slash")
            }
            .disabled(!selectionCanDisable || selectionIsBusy)
            .help("surveillance.camera.disable_selected.action")
        }

        ToolbarItem {
            Button {
                showInspector.toggle()
                if showInspector, let selectedCamera {
                    Task { await loadSnapshot(selectedCamera) }
                }
            } label: {
                Label("surveillance.snapshot.section.title", systemImage: "photo")
            }
            .disabled(selectedCamera == nil)
            .help(showInspector ? "surveillance.snapshot.hide.action" : "surveillance.snapshot.show.action")
        }

        ToolbarItem {
            Menu {
                Toggle("common.label.automatic_refresh", isOn: $autoRefresh)
                    .help("surveillance.auto_refresh.label")
            } label: {
                Label("common.label.refresh_options", systemImage: "ellipsis.circle")
            }
            .help("common.label.refresh_options")
        }

        ToolbarItem {
            Button {
                Task { await load() }
            } label: {
                Label("common.button.refresh", systemImage: "arrow.clockwise")
            }
            .help("surveillance.camera.refresh.action")
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
                .foregroundStyle(.readableSecondary)
            }
            Spacer()
            if viewModel.busyIDs.contains(camera.id) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "common.status.operation_in_progress", defaultValue: "Operation in progress for \(camera.name)"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cameraAccessibilityLabel(camera))
        .accessibilityActions {
            if !viewModel.busyIDs.contains(camera.id) {
                Button(camera.enabled ? "common.button.disable" : "common.button.enable") {
                    Task { await set(enabled: !camera.enabled, ids: [camera.id]) }
                }
                .help(camera.enabled ? "surveillance.camera.disable.hint" : "surveillance.camera.enable.hint")
            }
            Button("surveillance.snapshot.load.action") {
                selection = [camera.id]
                showInspector = true
                Task { await loadSnapshot(camera) }
            }
            .help("surveillance.snapshot.load.hint")
        }
    }

    @ViewBuilder
    private func cameraActions(_ camera: SurveillanceCamera) -> some View {
        Button(camera.enabled ? "common.button.disable" : "common.button.enable") {
            Task { await set(enabled: !camera.enabled, ids: [camera.id]) }
        }
        .help(camera.enabled ? "surveillance.camera.disable.hint" : "surveillance.camera.enable.hint")
        Divider()
        Button("surveillance.snapshot.section.title") {
            selection = [camera.id]
            showInspector = true
            Task { await loadSnapshot(camera) }
        }
        .help("surveillance.snapshot.show.hint")
    }

    @ViewBuilder
    private var inspector: some View {
        if let camera = selectedCamera {
            VStack(spacing: 0) {
                snapshotView(camera)
                    .frame(minHeight: 180, idealHeight: 240)
                Divider()
                Form {
                    Section("surveillance.camera.column") {
                        LabeledContent("common.column.name", value: camera.name)
                        LabeledContent("common.column.state", value: statusText(camera.status))
                        LabeledContent("common.status.enabled.feminine", value: camera.enabled ? String(localized: "common.answer.yes") : String(localized: "common.answer.no"))
                        if let address = addressText(camera) { LabeledContent("common.column.address", value: address) }
                        if let vendor = camera.vendor { LabeledContent("surveillance.camera.vendor.label", value: vendor) }
                        if let model = camera.model { LabeledContent("common.label.model", value: model) }
                    }
                    Section("common.label.video") {
                        if let resolution = camera.resolution { LabeledContent("surveillance.camera.resolution.label", value: resolution) }
                        if let fps = camera.framesPerSecond {
                            LabeledContent("surveillance.camera.frame_rate.label", value: String(localized: "surveillance.camera.frame_rate", defaultValue: "\(fps) frames per second"))
                        }
                        if let codec = codecText(camera.videoCodec) { LabeledContent("surveillance.camera.codec", value: codec) }
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
                        Label("surveillance.snapshot.refresh.action", systemImage: "camera.rotate")
                    }
                    .help("surveillance.snapshot.refresh.action")
                }
            }
            .accessibilityLabel(String(localized: "surveillance.snapshot.section.title_for_camera", defaultValue: "Snapshot and information for \(camera.name)"))
        } else {
            EmptyModuleView(
                title: "common.empty.selection",
                systemImage: "video",
                description: "surveillance.snapshot.no_selection.description"
            )
        }
    }

    @ViewBuilder
    private func snapshotView(_ camera: SurveillanceCamera) -> some View {
        if viewModel.isLoadingSnapshot && viewModel.snapshotCameraID == camera.id {
            ModuleLoadingView("surveillance.snapshot.loading")
        } else if let message = viewModel.snapshotErrorMessage, viewModel.snapshotCameraID == camera.id {
            ModuleErrorView(message: message) { Task { await loadSnapshot(camera) } }
        } else if viewModel.snapshotCameraID == camera.id,
                  let data = viewModel.snapshotData,
                  let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(String(localized: "surveillance.camera.snapshot.label", defaultValue: "Current snapshot from \(camera.name)"))
                .accessibilityAddTraits(.isImage)
                .padding(8)
        } else {
            EmptyModuleView(
                title: "surveillance.snapshot.empty",
                systemImage: "photo",
                description: "surveillance.snapshot.empty.description"
            )
        }
    }

    private var statusBar: some View {
        HStack {
            Text(viewModel.summary)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.readableSecondary)
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

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "surveillance.loading"),
            category: .progress,
            priority: .low
        )
        await viewModel.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { contentFocused = true }
        }
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
            VoiceOver.announce(String(localized: "surveillance.snapshot.loaded.announcement", defaultValue: "Snapshot loaded for \(camera.name)"))
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
        case 1: String(localized: "surveillance.camera.status.normal")
        case 2: String(localized: "surveillance.camera.status.deleted")
        case 3: String(localized: "surveillance.camera.status.disconnected")
        case 4: String(localized: "common.status.unavailable")
        case 5: String(localized: "surveillance.camera.status.ready")
        case 6: String(localized: "common.status.unreachable")
        case 7: String(localized: "common.status.disabled.feminine")
        case 8: String(localized: "surveillance.camera.status.unrecognized")
        case 9: String(localized: "surveillance.camera.configuration")
        case 10: String(localized: "surveillance.camera.status.server_disconnected")
        case 11: String(localized: "surveillance.camera.status.migrating")
        case 13: String(localized: "surveillance.camera.status.storage_removed")
        case 14: String(localized: "common.status.stopping")
        case 15: String(localized: "surveillance.camera.connection_history.unavailable")
        case 16: String(localized: "surveillance.camera.status.unauthorized")
        case 17: String(localized: "surveillance.camera.status.rtsp_error")
        case 18: String(localized: "surveillance.camera.status.no_video")
        default: String(localized: "common.status.unknown")
        }
    }
}
