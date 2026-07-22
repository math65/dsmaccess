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
            Text("Réglages généraux USB Copy")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($contentFocused)
                .padding()

            if isLoading {
                ModuleLoadingView("Chargement des réglages USB Copy…")
            } else if let settingsBinding {
                Form {
                    Picker("Volume du dépôt", selection: settingsBinding.repositoryVolumePath) {
                        ForEach(selectableVolumes, id: \.self) { path in
                            Text(volumeLabel(for: path)).tag(path)
                        }
                    }
                    .help("Volume qui contient la base de données et les versions USB Copy")

                    TextField(
                        "Nombre maximal de journaux",
                        value: settingsBinding.logRotateCount,
                        format: .number
                    )
                    .help("Conserver entre 5 et 100 000 entrées dans le journal USB Copy")

                    Toggle(
                        "Émettre un signal sonore au début et à la fin des tâches",
                        isOn: settingsBinding.beepOnTaskStartEnd
                    )

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityFocused($errorFocused)
                    }
                }
                .formStyle(.grouped)
            } else {
                ModuleErrorView(
                    message: errorMessage ?? String(localized: "Impossible de charger les réglages USB Copy."),
                    retry: { Task { await loadSettings() } }
                )
                .accessibilityFocused($errorFocused)
            }

            Divider()
            HStack {
                if isSaving { ProgressView("Enregistrement…").controlSize(.small) }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("Enregistrer", action: requestSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(settings == nil || isLoading || isSaving || !isValid)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 400)
        .confirmationDialog(
            "Déplacer le dépôt USB Copy ?",
            isPresented: $showsRepositoryMoveConfirmation
        ) {
            Button("Déplacer et enregistrer") { Task { await save() } }
            Button("Annuler", role: .cancel) { }
        } message: {
            if let settings {
                Text("Le dépôt USB Copy sera déplacé de « \(originalRepositoryVolumePath) » vers « \(settings.repositoryVolumePath) ». USB Copy peut être temporairement indisponible pendant le déplacement.")
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
        VoiceOver.announce(String(localized: "Chargement des réglages USB Copy…"), category: .progress)
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
        VoiceOver.announce(String(localized: "Enregistrement…"), category: .progress)
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
