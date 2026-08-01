//
//  DockerImageDetailSheet.swift
//  dsmaccess
//
//  What an image declares about itself: its command, the ports it exposes, the volumes it
//  expects and the environment variables it ships with.
//

import SwiftUI

struct DockerImageDetailSheet: View {
    let image: DockerImage
    let vm: DockerImagesViewModel

    @State private var detail: DockerImageDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @AccessibilityFocusState private var focusContent: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(image.displayName)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.button.close", role: .cancel) { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
        }
        .frame(minWidth: 640, minHeight: 560)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ModuleLoadingView("containers.image.detail.loading")
                .accessibilityFocused($focusContent)
        } else if let errorMessage {
            ModuleErrorView(message: errorMessage) {
                Task { await load() }
            }
            .accessibilityFocused($focusContent)
        } else if let detail {
            Form {
                Section("common.label.information") {
                    LabeledContent("common.column.name", value: image.displayName)
                    LabeledContent("containers.image.detail.identifier", value: shortIdentifier(detail.id))
                    if let size = detail.sizeBytes ?? image.sizeBytes {
                        LabeledContent("common.column.size", value: size.formatted(.byteCount(style: .file)))
                    }
                    if let virtualSize = detail.virtualSizeBytes {
                        LabeledContent(
                            "containers.image.detail.virtual_size",
                            value: virtualSize.formatted(.byteCount(style: .file))
                        )
                    }
                    if let createdAt = image.createdAt {
                        LabeledContent(
                            "common.column.creation_date",
                            value: createdAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    if !detail.author.isEmpty {
                        LabeledContent("containers.image.detail.author", value: detail.author)
                    }
                    if !detail.dockerVersion.isEmpty {
                        LabeledContent("containers.image.detail.docker_version", value: detail.dockerVersion)
                    }
                    if let digest = detail.digest {
                        LabeledContent("containers.image.detail.digest", value: shortIdentifier(digest))
                    }
                }
                .labeledContentStyle(.readable)

                if !detail.entrypoint.isEmpty || !detail.command.isEmpty {
                    Section("containers.image.detail.execution") {
                        if !detail.entrypoint.isEmpty {
                            LabeledContent(
                                "containers.image.detail.entrypoint",
                                value: detail.entrypoint.joined(separator: " ")
                            )
                        }
                        if !detail.command.isEmpty {
                            LabeledContent(
                                "containers.image.detail.command",
                                value: detail.command.joined(separator: " ")
                            )
                        }
                    }
                    .labeledContentStyle(.readable)
                }

                Section("containers.image.detail.ports") {
                    if detail.exposedPorts.isEmpty {
                        Text("containers.image.detail.ports.none")
                            .foregroundStyle(.readableSecondary)
                    } else {
                        ForEach(detail.exposedPorts) { port in
                            Text(port.displayName)
                        }
                    }
                }

                Section("containers.image.detail.volumes") {
                    if detail.volumes.isEmpty {
                        Text("containers.image.detail.volumes.none")
                            .foregroundStyle(.readableSecondary)
                    } else {
                        ForEach(detail.volumes, id: \.self) { volume in
                            Text(volume)
                        }
                    }
                }

                Section("containers.image.detail.environment") {
                    if detail.environment.isEmpty {
                        Text("containers.image.detail.environment.none")
                            .foregroundStyle(.readableSecondary)
                    } else {
                        ForEach(detail.environment) { variable in
                            LabeledContent(variable.key, value: variable.value)
                        }
                        .labeledContentStyle(.readable)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel(String(
                localized: "common.title.information_for",
                defaultValue: "Information for \(image.displayName)"
            ))
            .accessibilityFocused($focusContent)
        }
    }

    /// A sha256 identifier is 71 characters of hexadecimal, which is unreadable spelled out.
    /// Docker itself shows the first twelve, and so does DSM.
    private func shortIdentifier(_ identifier: String) -> String {
        let value = identifier.hasPrefix("sha256:")
            ? String(identifier.dropFirst("sha256:".count))
            : identifier
        return String(value.prefix(12))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await vm.detail(for: image)
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
        }
        guard !Task.isCancelled else { return }
        focusContent = true
    }
}
