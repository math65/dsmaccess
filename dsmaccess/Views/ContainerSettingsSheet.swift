//
//  ContainerSettingsSheet.swift
//  dsmaccess
//
//  Editing the settings DSM keeps on a container.
//

import SwiftUI

/// DSM's Settings screen for a container. It edits a few fields of the creation profile and
/// hands the rest back untouched, so a field this app does not model survives the save.
///
/// Only the fields whose write was measured against the NAS are offered. Ports, volumes and
/// environment variables are part of the same profile but were never written, and a wrong
/// shape there would break the container rather than the form.
struct ContainerSettingsSheet: View {
    let container: ContainerItem
    let vm: ContainersViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var profile: ContainerProfile?
    @State private var name = ""
    @State private var limitsMemory = false
    @State private var memoryLimitMB = 512
    @State private var restartsAutomatically = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusStatus: Bool

    /// DSM stores the limit in bytes and treats 0 as "no limit".
    private static let bytesPerMB: Int64 = 1024 * 1024

    var body: some View {
        VStack(spacing: 0) {
            Text("containers.settings.title")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            Divider()
            content
            Divider()

            HStack {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("containers.settings.saving")
                }
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("common.button.save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(profile == nil || isSaving || trimmedName.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 420)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, profile == nil {
            ModuleErrorView(message: errorMessage) { Task { await load() } }
                .accessibilityFocused($focusStatus)
        } else if profile == nil {
            ModuleLoadingView("containers.settings.loading")
                .accessibilityFocused($focusStatus)
        } else {
            Form {
                Section("containers.settings.identity") {
                    TextField("containers.column.name", text: $name)
                        .help("containers.settings.name.hint")
                }

                Section("containers.settings.resources") {
                    Toggle("containers.settings.memory_limit.label", isOn: $limitsMemory)
                        .accessibilityHint("containers.settings.memory_limit.hint")
                    if limitsMemory {
                        TextField(
                            "containers.settings.memory_limit.value",
                            value: $memoryLimitMB,
                            format: .number
                        )
                        .help("containers.settings.memory_limit.value.hint")
                    }
                }

                Section("containers.settings.behavior") {
                    Toggle("containers.settings.restart.label", isOn: $restartsAutomatically)
                        .accessibilityHint("containers.settings.restart.hint")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($focusStatus)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("containers.settings.fields.label")
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() async {
        errorMessage = nil
        do {
            let loaded = try await vm.profile(of: container)
            guard !Task.isCancelled else { return }
            profile = loaded
            name = container.name
            limitsMemory = loaded.memoryLimit > 0
            if loaded.memoryLimit > 0 {
                memoryLimitMB = Int(loaded.memoryLimit / Self.bytesPerMB)
            }
            restartsAutomatically = loaded.restartsAutomatically
            focusHeading = true
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            focusStatus = true
        }
    }

    private func save() async {
        guard var edited = profile else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        edited.memoryLimit = limitsMemory ? Int64(memoryLimitMB) * Self.bytesPerMB : 0
        edited.restartsAutomatically = restartsAutomatically

        let outcome = await vm.updateProfile(
            of: container,
            editName: trimmedName,
            profile: edited
        )
        VoiceOver.announce(outcome, priority: .high)
        if case .failure(let message) = outcome {
            errorMessage = message
            focusStatus = true
        } else {
            dismiss()
        }
    }
}
