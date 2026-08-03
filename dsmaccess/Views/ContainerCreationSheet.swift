//
//  ContainerCreationSheet.swift
//  dsmaccess
//
//  Creating a container from an image already on the NAS.
//

import SwiftUI

/// Collects what `SYNO.Docker.Container create` needs. Ports, volumes and variables are here
/// and not in the settings screen because only creation honours them — `set` accepts them and
/// applies nothing, measured against the NAS.
struct ContainerCreationSheet: View {
    let vm: ContainersViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ContainerDraft()
    @State private var images: [DockerImage] = []
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("containers.create.title")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            Divider()

            Form {
                Section("containers.create.section.image") {
                    Picker("common.label.image", selection: $draft.image) {
                        Text("containers.create.image.none").tag("")
                        ForEach(imageChoices, id: \.self) { choice in
                            Text(choice).tag(choice)
                        }
                    }
                    .help("containers.create.image.hint")
                    TextField("containers.column.name", text: $draft.name)
                        .help("containers.create.name.hint")
                    TextField("containers.create.command", text: $draft.command)
                        .help("containers.create.command.hint")
                }

                Section("containers.settings.behavior") {
                    Toggle("containers.settings.restart.label", isOn: $draft.restartsAutomatically)
                        .accessibilityHint("containers.settings.restart.hint")
                    Toggle("containers.create.start_now", isOn: $draft.startsImmediately)
                        .accessibilityHint("containers.create.start_now.hint")
                    Toggle("containers.settings.memory_limit.label", isOn: $draft.limitsMemory)
                        .accessibilityHint("containers.settings.memory_limit.hint")
                    if draft.limitsMemory {
                        TextField(
                            "containers.settings.memory_limit.value",
                            value: $draft.memoryLimitMB,
                            format: .number
                        )
                        .help("containers.settings.memory_limit.value.hint")
                    }
                }

                Section("containers.create.section.ports") {
                    ForEach($draft.ports) { $port in
                        LabeledContent("containers.create.port.entry") {
                            HStack {
                                TextField(
                                    "containers.create.port.container",
                                    value: $port.containerPort,
                                    format: .number
                                )
                                TextField(
                                    "containers.create.port.host",
                                    value: $port.hostPort,
                                    format: .number
                                )
                                Picker("common.column.protocol", selection: $port.networkProtocol) {
                                    Text(verbatim: "TCP").tag("tcp")
                                    Text(verbatim: "UDP").tag("udp")
                                }
                                .labelsHidden()
                            }
                        }
                    }
                    Text("containers.create.port.automatic")
                        .font(.caption)
                        .foregroundStyle(.readableSecondary)
                    HStack {
                        Button("containers.create.port.add") {
                            draft.ports.append(ContainerPortBinding())
                        }
                        Button("containers.create.port.remove") {
                            _ = draft.ports.popLast()
                        }
                        .disabled(draft.ports.isEmpty)
                    }
                }

                Section("containers.create.section.volumes") {
                    ForEach($draft.volumes) { $volume in
                        LabeledContent("containers.create.volume.entry") {
                            HStack {
                                TextField("containers.create.volume.host", text: $volume.hostPath)
                                TextField("containers.create.volume.mount", text: $volume.mountPoint)
                                Toggle("common.permission.read_only", isOn: $volume.isReadOnly)
                            }
                        }
                    }
                    HStack {
                        Button("containers.create.volume.add") {
                            draft.volumes.append(ContainerVolumeBinding())
                        }
                        Button("containers.create.volume.remove") {
                            _ = draft.volumes.popLast()
                        }
                        .disabled(draft.volumes.isEmpty)
                    }
                }

                Section("containers.create.section.environment") {
                    ForEach($draft.environment) { $variable in
                        LabeledContent("containers.create.environment.entry") {
                            HStack {
                                TextField("containers.create.environment.key", text: $variable.key)
                                TextField("containers.create.environment.value", text: $variable.value)
                            }
                        }
                    }
                    HStack {
                        Button("containers.create.environment.add") {
                            draft.environment.append(ContainerEnvironmentVariable())
                        }
                        Button("containers.create.environment.remove") {
                            _ = draft.environment.popLast()
                        }
                        .disabled(draft.environment.isEmpty)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($focusError)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("containers.create.fields.label")

            Divider()

            HStack {
                if vm.isCreating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("containers.create.in_progress")
                }
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(vm.isCreating)
                Button("containers.create.button") { Task { await create() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.isComplete || vm.isCreating)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 560)
        .task {
            images = (try? await vm.availableImages()) ?? []
            focusHeading = true
        }
    }

    /// An image is named `repository:tag` when creating a container, as DSM does.
    private var imageChoices: [String] {
        images
            .flatMap { image in image.tags.map { "\(image.repository):\($0)" } }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func create() async {
        errorMessage = nil
        let outcome = await vm.create(draft)
        VoiceOver.announce(outcome, priority: .high)
        if case .failure(let message) = outcome {
            errorMessage = message
            focusError = true
        } else {
            dismiss()
        }
    }
}
