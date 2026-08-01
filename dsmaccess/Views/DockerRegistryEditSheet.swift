//
//  DockerRegistryEditSheet.swift
//  dsmaccess
//
//  Adding a registry, or editing one. DSM designates the registry being edited by its former
//  name, which is what lets this form rename it.
//

import SwiftUI

struct DockerRegistryEditSheet: View {
    let vm: DockerRegistriesViewModel
    /// The registry being edited, or nil when adding one.
    let registry: DockerRegistry?

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var trustsSelfSignedCertificate = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var nameFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { registry != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("common.label.information") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("containers.registry.field.name", text: $name)
                            .accessibilityFocused($nameFocused)
                            .accessibilityHint(nameProblem ?? String(localized: "containers.registry.field.name.hint"))
                            .disabled(isSaving)
                        if let nameProblem {
                            Text(nameProblem)
                                .font(.caption)
                                .foregroundStyle(.readableRed)
                        }
                    }

                    TextField("containers.registry.field.url", text: $url, prompt: Text(verbatim: "https://registry.example.com"))
                        .accessibilityHint("containers.registry.field.url.hint")
                        .disabled(isSaving)
                }

                Section("containers.registry.section.credentials") {
                    TextField("containers.registry.field.username", text: $username)
                        .accessibilityHint("containers.registry.field.username.hint")
                        .disabled(isSaving)

                    SecureField("containers.registry.field.password", text: $password)
                        .accessibilityHint(isEditing
                                           ? String(localized: "containers.registry.field.password.hint_edit")
                                           : String(localized: "containers.registry.field.password.hint"))
                        .disabled(isSaving)

                    if isEditing {
                        // DSM never returns a stored password, so there is nothing to prefill
                        // and nothing to compare against.
                        Text("containers.registry.field.password.not_readable")
                            .font(.caption)
                            .foregroundStyle(.readableSecondary)
                    }
                }

                Section {
                    Toggle("containers.registry.field.trust_certificate", isOn: $trustsSelfSignedCertificate)
                        .accessibilityHint("containers.registry.field.trust_certificate.hint")
                        .disabled(isSaving)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($errorFocused)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel(isEditing
                                ? String(localized: "containers.registry.edit.title")
                                : String(localized: "containers.registry.add.title"))
            .navigationTitle(isEditing ? "containers.registry.edit.title" : "containers.registry.add.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.button.cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "common.button.save" : "containers.registry.action.add") {
                        Task { await save() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
                if isSaving {
                    ToolbarItem(placement: .status) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("containers.registry.save.in_progress")
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            if let registry {
                name = registry.name
                url = registry.url
                username = registry.username
                trustsSelfSignedCertificate = registry.trustsSelfSignedCertificate
            }
            await Task.yield()
            nameFocused = true
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameProblem: String? {
        guard !trimmedName.isEmpty else { return nil }
        let clashes = vm.registries.contains {
            $0.name == trimmedName && $0.name != registry?.name
        }
        return clashes ? String(localized: "containers.registry.error.name_taken") : nil
    }

    /// DSM answers 101 without a URL, so the form asks for one rather than letting the NAS
    /// refuse a half-filled registry.
    private var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && !trimmedURL.isEmpty && nameProblem == nil
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        VoiceOver.announce(
            String(localized: "containers.registry.save.in_progress"),
            category: .progress
        )

        let outcome: DSMOperationOutcome
        if let registry {
            outcome = await vm.update(
                registry,
                name: trimmedName,
                url: trimmedURL,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                trustsSelfSignedCertificate: trustsSelfSignedCertificate
            )
        } else {
            outcome = await vm.create(
                name: trimmedName,
                url: trimmedURL,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                trustsSelfSignedCertificate: trustsSelfSignedCertificate
            )
        }

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
