//
//  DSMUpdateView.swift
//  dsmaccess
//
//  Manual DSM update from a .pat file.
//

import SwiftUI
import UniformTypeIdentifiers

struct DSMUpdateView: View {
    @State private var viewModel: DSMUpdateViewModel
    @State private var showsFileImporter = false
    @State private var showsConfirmation = false
    @State private var operationTask: Task<Void, Never>?
    @AccessibilityFocusState private var focusContent: Bool
    @AccessibilityFocusState private var focusWarning: Bool

    init(session: SessionStore) {
        _viewModel = State(initialValue: DSMUpdateViewModel(session: session))
    }

    var body: some View {
        content
            .navigationTitle("common.section.dsm_update")
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await viewModel.load() }
                    } label: {
                        Label("common.button.refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isBusy)
                    .help("dsm_update.version.refresh.hint")
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                handleSelection(result)
            }
            .sheet(isPresented: $showsConfirmation) {
                DSMUpdateConfirmationSheet(
                    currentVersion: viewModel.currentVersion,
                    fileName: viewModel.selectedFile?.lastPathComponent ?? "",
                    preCheck: viewModel.preCheck
                ) {
                    startUpgrade()
                }
            }
            .task { await load() }
            .onDisappear { operationTask?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ModuleLoadingView("dsm_update.version.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage = viewModel.errorMessage {
            ModuleErrorView(message: errorMessage) {
                Task { await load() }
            }
            .accessibilityFocused($focusContent)
        } else {
            Form {
                Section {
                    Text("dsm_update.first_version.warning")
                        .font(.callout)
                        .foregroundStyle(.readableOrange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityFocused($focusContent)
                }

                Section("common.label.nas") {
                    LabeledContent("common.label.model") { Text(viewModel.modelName ?? "—") }
                    LabeledContent("common.label.installed_version") { Text(viewModel.currentVersion ?? "—") }
                        .labeledContentStyle(.readable)
                }

                Section("dsm_update.file.section") {
                    Text(viewModel.statusText)
                        .foregroundStyle(.readableSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("dsm_update.file.choose.button") { showsFileImporter = true }
                        .disabled(viewModel.isBusy)
                        .help("dsm_update.file.choose.hint")
                    if viewModel.selectedFile != nil {
                        Button("dsm_update.upload.button") { uploadAndCheck() }
                            .disabled(viewModel.isBusy || viewModel.stage == .awaitingConfirmation)
                            .help("dsm_update.upload.button.hint")
                    }
                }

                if viewModel.stage == .uploading, let fraction = viewModel.transferProgress?.fractionCompleted {
                    Section("common.status.sending") {
                        ProgressView(value: fraction)
                            .accessibilityLabel("dsm_update.upload.progress")
                            .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
                    }
                }

                if let preCheck = viewModel.preCheck {
                    Section("dsm_update.precheck.section") {
                        Text(warningText(for: preCheck))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityFocused($focusWarning)
                        Button("dsm_update.install.button") { showsConfirmation = true }
                            .disabled(viewModel.isBusy)
                            .help("dsm_update.install.button.hint")
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("dsm_update.details.label")
        }
    }

    /// The contents of the pre-check could not be measured on a real NAS: when DSM answers in
    /// an unknown shape, the screen says so instead of letting the user believe there is no
    /// consequence.
    private func warningText(_ preCheck: DSMUpgradePreCheck) -> String { warningText(for: preCheck) }

    private func warningText(for preCheck: DSMUpgradePreCheck) -> String {
        guard preCheck.isUnderstood else {
            return String(
                localized: "dsm_update.precheck.unreadable_details"
            )
        }
        guard !preCheck.unsupportedPackages.isEmpty else {
            return String(localized: "dsm_update.precheck.no_dropped_packages")
        }
        let liste = preCheck.unsupportedPackages.formatted(.list(type: .and))
        return String(localized: "dsm_update.precheck.dropped_packages", defaultValue: "These packages will no longer be supported after the update: \(liste).")
    }

    private func load() async {
        VoiceOver.announce(
            String(localized: "dsm_update.version.loading"),
            category: .progress,
            priority: .low
        )
        await viewModel.load()
        guard !Task.isCancelled else { return }
        await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        VoiceOver.announce(
            viewModel.summary,
            category: viewModel.errorMessage == nil ? .result : .error
        )
    }

    private func handleSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.pathExtension.caseInsensitiveCompare("pat") == .orderedSame else {
                viewModel.errorMessage = String(
                    localized: "dsm_update.file.wrong_type.error"
                )
                VoiceOver.announce(viewModel.errorMessage ?? "", category: .error, priority: .high)
                return
            }
            viewModel.selectFile(url)
            VoiceOver.announce(viewModel.statusText, category: .result)
        case .failure(let error):
            guard (error as? CocoaError)?.code != .userCancelled else { return }
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func uploadAndCheck() {
        guard operationTask == nil else { return }
        VoiceOver.announce(
            String(localized: "common.status.sending.description"),
            category: .progress,
            priority: .high
        )
        operationTask = Task {
            let outcome = await viewModel.uploadAndCheck()
            operationTask = nil
            VoiceOver.announce(outcome, priority: .high)
            if case .success = outcome { focusWarning = true }
        }
    }

    private func startUpgrade() {
        guard operationTask == nil else { return }
        VoiceOver.announce(
            String(localized: "dsm_update.install.started"),
            category: .progress,
            priority: .high
        )
        operationTask = Task {
            let outcome = await viewModel.startUpgrade()
            operationTask = nil
            VoiceOver.announce(outcome, priority: .high)
        }
    }
}

/// Last stop before an operation that takes the NAS down for some twenty minutes: the
/// consequences are stated, and the checkbox must be ticked to continue.
private struct DSMUpdateConfirmationSheet: View {
    let currentVersion: String?
    let fileName: String
    let preCheck: DSMUpgradePreCheck?
    let onConfirm: () -> Void

    @State private var hasUnderstood = false
    @AccessibilityFocusState private var focusTitle: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("dsm_update.install.confirm.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            Text(consequences)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("dsm_update.install.acknowledge.label", isOn: $hasUnderstood)
                .help("dsm_update.install.acknowledge.hint")

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("dsm_update.install.cancel.hint")
                Button("dsm_update.install.confirm.button") {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasUnderstood)
                .help("dsm_update.install.confirm.hint")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            focusTitle = true
            VoiceOver.announce(
                String(localized: "dsm_update.install.confirm.title"),
                category: .navigation
            )
        }
    }

    private var consequences: String {
        let version = currentVersion ?? String(localized: "dsm_update.version.unknown")
        let paquets = preCheck?.unsupportedPackages ?? []
        if paquets.isEmpty {
            return String(
                localized: "dsm_update.install.confirm.message", defaultValue: "The NAS will move from version \(version) to the one in the file \(fileName). The installation takes 10 to 20 minutes, during which the NAS is unusable and all its services stop. Going back to the previous version is not possible."
            )
        }
        let liste = paquets.formatted(.list(type: .and))
        return String(
            localized: "dsm_update.install.confirm.message_with_dropped_packages", defaultValue: "The NAS will move from version \(version) to the one in the file \(fileName). These packages will no longer be supported: \(liste). The installation takes 10 to 20 minutes, during which the NAS is unusable and all its services stop. Going back to the previous version is not possible."
        )
    }
}
