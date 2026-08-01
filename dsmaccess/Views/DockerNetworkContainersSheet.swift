//
//  DockerNetworkContainersSheet.swift
//  dsmaccess
//
//  Which containers a network carries. DSM takes the wanted final set and works out the
//  attachments and detachments itself, so the sheet ticks a list rather than offering two
//  separate connect and disconnect actions.
//

import SwiftUI

struct DockerNetworkContainersSheet: View {
    let network: DockerNetwork
    let vm: DockerNetworksViewModel

    @State private var containers: [DockerNetworkContainer] = []
    @State private var attached: Set<String> = []
    @State private var initialAttached: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var loadErrorMessage: String?
    @State private var saveErrorMessage: String?
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(
                    localized: "containers.network.containers.title",
                    defaultValue: "Containers of \(network.name)"
                ))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.button.cancel", role: .cancel) { dismiss() }
                            .keyboardShortcut(.cancelAction)
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.button.apply") { Task { await apply() } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(!canApply)
                    }
                    if isSaving {
                        ToolbarItem(placement: .status) {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("containers.network.containers.saving")
                        }
                    }
                }
        }
        .frame(minWidth: 520, minHeight: 460)
        .task {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ModuleLoadingView("containers.network.containers.loading")
                .accessibilityFocused($contentFocused)
        } else if let loadErrorMessage {
            ModuleErrorView(message: loadErrorMessage) {
                Task { await load() }
            }
            .accessibilityFocused($contentFocused)
        } else if containers.isEmpty {
            EmptyModuleView(
                title: "containers.network.containers.empty.title",
                systemImage: "shippingbox",
                description: "containers.network.containers.empty.description"
            )
            .accessibilityFocused($contentFocused)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Form {
                    Section("containers.network.containers.section") {
                        ForEach(containers) { container in
                            Toggle(container.name, isOn: binding(for: container.name))
                                .disabled(isSaving)
                        }
                    }
                    if let saveErrorMessage {
                        Section {
                            Label(saveErrorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.readableRed)
                                .accessibilityFocused($errorFocused)
                        }
                    }
                }
                .formStyle(.grouped)
                .accessibilityFocused($contentFocused)
            }
        }
    }

    private func binding(for name: String) -> Binding<Bool> {
        Binding(
            get: { attached.contains(name) },
            set: { isOn in
                if isOn {
                    attached.insert(name)
                } else {
                    attached.remove(name)
                }
            }
        )
    }

    private var canApply: Bool {
        !isSaving && !isLoading && loadErrorMessage == nil && attached != initialAttached
    }

    private func load() async {
        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await vm.attachableContainers()
            guard !Task.isCancelled else { return }
            containers = loaded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            // What is already attached comes from the network itself: list_container only says
            // what could be attached, never what is.
            let current = Set(network.containerNames)
            attached = current
            initialAttached = current
            contentFocused = true
        } catch {
            guard !Task.isCancelled, !DSMError.isCancellation(error) else { return }
            loadErrorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            VoiceOver.announce(loadErrorMessage ?? "", category: .error, priority: .high)
        }
    }

    private func apply() async {
        guard canApply else { return }
        isSaving = true
        saveErrorMessage = nil
        VoiceOver.announce(
            String(localized: "containers.network.containers.saving"),
            category: .progress
        )
        let outcome = await vm.setContainers(of: network, to: attached.sorted())
        isSaving = false
        VoiceOver.announce(outcome, priority: .high)
        switch outcome {
        case .success:
            dismiss()
        case .failure(let message):
            saveErrorMessage = message
            errorFocused = true
        case .cancelled:
            break
        }
    }
}
