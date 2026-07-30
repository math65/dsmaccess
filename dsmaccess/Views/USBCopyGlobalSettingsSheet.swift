//
//  USBCopyGlobalSettingsSheet.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyGlobalSettingsSheet: View {
    let load: () async throws -> USBCopyGlobalSettings
    let loadVolumePaths: () async throws -> [String]
    let onSave: (USBCopyGlobalSettings) async -> DSMOperationOutcome

    @State private var settings: USBCopyGlobalSettings?
    @State private var volumePaths: [String] = []
    @State private var originalRepositoryVolumePath = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsRepositoryMoveConfirmation = false
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("usb_copy.settings.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($contentFocused)
                .padding()

            if isLoading {
                ModuleLoadingView("usb_copy.settings.loading")
            } else if let settingsBinding {
                Form {
                    Picker("usb_copy.settings.repository_volume.label", selection: settingsBinding.repositoryVolumePath) {
                        ForEach(selectableVolumes, id: \.self) { path in
                            Text(volumeLabel(for: path)).tag(path)
                        }
                    }
                    .help("usb_copy.settings.repository_volume.description")

                    TextField(
                        "usb_copy.settings.max_log_entries.label",
                        value: settingsBinding.logRotateCount,
                        format: .number
                    )
                    .help("usb_copy.settings.max_log_entries.description")

                    Toggle(
                        "usb_copy.settings.beep.label",
                        isOn: settingsBinding.beepOnTaskStartEnd
                    )

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($errorFocused)
                    }
                }
                .formStyle(.grouped)
            } else {
                ModuleErrorView(
                    message: errorMessage ?? String(localized: "usb_copy.settings.load.error"),
                    retry: { Task { await loadSettings() } }
                )
                .accessibilityFocused($errorFocused)
            }

            Divider()
            HStack {
                if isSaving { ProgressView("common.status.saving").controlSize(.small) }
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("common.button.save", action: requestSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(settings == nil || isLoading || isSaving || !isValid)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 400)
        .confirmationDialog(
            "usb_copy.settings.move_repository.title",
            isPresented: $showsRepositoryMoveConfirmation
        ) {
            Button("usb_copy.settings.move_repository.confirm") { Task { await save() } }
            Button("common.button.cancel", role: .cancel) { }
        } message: {
            if let settings {
                Text(String(localized: "usb_copy.settings.move_repository.message", defaultValue: "The USB Copy repository will be moved from “\(originalRepositoryVolumePath)” to “\(settings.repositoryVolumePath)”. USB Copy may be temporarily unavailable during the move."))
            }
        }
        .task {
            await loadSettings()
            guard !Task.isCancelled else { return }
            contentFocused = true
        }
    }

    private var settingsBinding: Binding<USBCopyGlobalSettings>? {
        guard settings != nil else { return nil }
        return Binding(
            get: { settings ?? USBCopyGlobalSettings(
                repositoryVolumePath: "/volume1",
                logRotateCount: 100_000,
                beepOnTaskStartEnd: true
            ) },
            set: { settings = $0 }
        )
    }

    private var selectableVolumes: [String] {
        var values = Set(volumePaths)
        if let current = settings?.repositoryVolumePath { values.insert(current) }
        return values.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var isValid: Bool {
        guard let settings else { return false }
        return !settings.repositoryVolumePath.isEmpty && (5...100_000).contains(settings.logRotateCount)
    }

    private func loadSettings() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        VoiceOver.announce(String(localized: "usb_copy.settings.loading"), category: .progress)
        do {
            async let loadedSettings = load()
            async let loadedVolumePaths = loadVolumePaths()
            let (newSettings, newVolumePaths) = try await (loadedSettings, loadedVolumePaths)
            settings = newSettings
            originalRepositoryVolumePath = newSettings.repositoryVolumePath
            volumePaths = newVolumePaths
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            errorFocused = true
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }

    private func requestSave() {
        guard let settings, isValid else { return }
        if settings.repositoryVolumePath != originalRepositoryVolumePath {
            showsRepositoryMoveConfirmation = true
        } else {
            Task { await save() }
        }
    }

    private func save() async {
        guard let settings, isValid else { return }
        isSaving = true
        errorMessage = nil
        VoiceOver.announce(String(localized: "common.status.saving"), category: .progress)
        let outcome = await onSave(settings)
        isSaving = false
        VoiceOver.announce(outcome, priority: .high)
        switch outcome {
        case .success:
            dismiss()
        case .failure(let message):
            errorMessage = message
            errorFocused = true
        case .cancelled:
            break
        }
    }
}
