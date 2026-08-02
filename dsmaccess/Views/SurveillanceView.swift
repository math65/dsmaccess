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
    @State private var order = [KeyPathComparator(\SurveillanceCamera.name, order: .forward)]
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
            Table(
                filteredCameras.sorted(using: order),
                selection: $selection,
                sortOrder: $order
            ) {
                TableColumn("common.column.name", value: \.name) { camera in
                    Text(camera.name)
                }
                TableColumn("common.column.state", value: \.sortableStatus) { camera in
                    Text(camera.statusDescription)
                }
                TableColumn("common.status.enabled.feminine", value: \.sortableEnabled) { camera in
                    Text(camera.enabled
                        ? String(localized: "common.answer.yes")
                        : String(localized: "common.answer.no"))
                }
                TableColumn("common.column.address", value: \.sortableAddress) { camera in
                    Text(camera.addressWithPort ?? "—")
                }
                TableColumn("surveillance.camera.vendor.label", value: \.sortableVendor) { camera in
                    Text(camera.vendor ?? "—")
                }
                TableColumn("common.label.model", value: \.sortableModel) { camera in
                    Text(camera.model ?? "—")
                }
                TableColumn("surveillance.camera.resolution.label", value: \.sortableResolution) { camera in
                    Text(camera.resolution ?? "—")
                }
                TableColumn("surveillance.camera.codec", value: \.sortableCodec) { camera in
                    Text(camera.codecName ?? "—")
                }
            }
            .accessibilityLabel("surveillance.cameras.title")
            .accessibilityFocused($contentFocused)
            .contextMenu(forSelectionType: String.self) { ids in
                if let camera = viewModel.cameras.first(where: { ids.contains($0.id) }) {
                    cameraActions(camera)
                }
            }
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
                        LabeledContent("common.column.state", value: camera.statusDescription)
                        LabeledContent("common.status.enabled.feminine", value: camera.enabled ? String(localized: "common.answer.yes") : String(localized: "common.answer.no"))
                        if let address = camera.addressWithPort { LabeledContent("common.column.address", value: address) }
                        if let vendor = camera.vendor { LabeledContent("surveillance.camera.vendor.label", value: vendor) }
                        if let model = camera.model { LabeledContent("common.label.model", value: model) }
                    }
                    Section("common.label.video") {
                        if let resolution = camera.resolution { LabeledContent("surveillance.camera.resolution.label", value: resolution) }
                        if let fps = camera.framesPerSecond {
                            LabeledContent("surveillance.camera.frame_rate.label", value: String(localized: "surveillance.camera.frame_rate", defaultValue: "\(fps) frames per second"))
                        }
                        if let codec = camera.codecName { LabeledContent("surveillance.camera.codec", value: codec) }
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
}
