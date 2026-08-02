//
//  DockerNetworkCreationSheet.swift
//  dsmaccess
//
//  Creating a container network. DSM greys out the address fields in automatic mode; the app
//  hides them instead, so a screen reader is not walked through fields that do nothing.
//

import SwiftUI

struct DockerNetworkCreationSheet: View {
    let vm: DockerNetworksViewModel

    @State private var name = ""
    @State private var isManual = false
    @State private var subnet = ""
    @State private var ipRange = ""
    @State private var gateway = ""
    @State private var disablesMasquerade = false
    @State private var enablesIPv6 = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var nameFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("common.label.information") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("containers.network.create.name", text: $name)
                            .accessibilityFocused($nameFocused)
                            .accessibilityHint(nameProblem ?? String(localized: "containers.network.create.name.rule"))
                            .disabled(isCreating)
                        if let nameProblem {
                            Text(nameProblem)
                                .font(.caption)
                                .foregroundStyle(.readableRed)
                        }
                    }
                }

                Section("containers.network.create.addressing") {
                    Picker("containers.network.create.addressing", selection: $isManual) {
                        Text("containers.network.create.addressing.automatic").tag(false)
                        Text("containers.network.create.addressing.manual").tag(true)
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(isCreating)

                    if isManual {
                        TextField("containers.network.create.subnet", text: $subnet)
                            .accessibilityHint("containers.network.create.subnet.hint")
                            .disabled(isCreating)
                        TextField("containers.network.create.iprange", text: $ipRange)
                            .accessibilityHint("containers.network.create.iprange.hint")
                            .disabled(isCreating)
                        TextField("containers.network.create.gateway", text: $gateway)
                            .accessibilityHint("containers.network.create.gateway.hint")
                            .disabled(isCreating)
                        Text("containers.network.create.manual.rule")
                            .font(.caption)
                            .foregroundStyle(.readableSecondary)
                    }
                }

                Section {
                    Toggle("containers.network.create.ipv6", isOn: $enablesIPv6)
                        .disabled(isCreating)
                    Toggle("containers.network.create.disable_masquerade", isOn: $disablesMasquerade)
                        .accessibilityHint("containers.network.create.disable_masquerade.hint")
                        .disabled(isCreating)
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
            .accessibilityLabel("containers.network.create.fields.label")
            .navigationTitle("containers.network.create.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.button.cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.button.create") { Task { await create() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canCreate)
                }
                if isCreating {
                    ToolbarItem(placement: .status) {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("containers.network.create.in_progress")
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .task {
            await Task.yield()
            nameFocused = true
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameProblem: String? {
        guard !trimmedName.isEmpty else { return nil }
        guard !vm.networks.contains(where: { $0.name == trimmedName }) else {
            return String(localized: "containers.network.create.error.name_taken_short")
        }
        return nil
    }

    private var addressing: DockerNetworkAddressing {
        guard isManual else { return .automatic }
        return .manual(
            subnet: subnet.trimmingCharacters(in: .whitespaces),
            ipRange: ipRange.trimmingCharacters(in: .whitespaces),
            gateway: gateway.trimmingCharacters(in: .whitespaces)
        )
    }

    /// DSM refuses a manual network unless all three address fields are filled, so the form
    /// asks for the three rather than letting the NAS answer for a blank one.
    private var canCreate: Bool {
        guard !isCreating, !trimmedName.isEmpty, nameProblem == nil else { return false }
        guard case .manual(let subnet, let ipRange, let gateway) = addressing else { return true }
        return !subnet.isEmpty && !ipRange.isEmpty && !gateway.isEmpty
    }

    private func create() async {
        guard canCreate else { return }
        isCreating = true
        errorMessage = nil
        VoiceOver.announce(
            String(localized: "containers.network.create.in_progress"),
            category: .progress
        )
        let outcome = await vm.create(
            name: trimmedName,
            addressing: addressing,
            disablesMasquerade: disablesMasquerade,
            enablesIPv6: enablesIPv6
        )
        isCreating = false
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
