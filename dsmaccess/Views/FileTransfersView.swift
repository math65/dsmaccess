//
//  FileTransfersView.swift
//  dsmaccess
//
//  File d'attente accessible des transferts File Station.
//

import SwiftUI

struct FileTransfersView: View {
    @Bindable var vm: FileBrowserViewModel
    let cancelActiveTransfers: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusHeading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("common.label.transfers")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            if vm.transfers.isEmpty {
                ContentUnavailableView(
                    "transfers.empty",
                    systemImage: "arrow.up.arrow.down",
                    description: Text("transfers.empty.description")
                )
            } else {
                List(vm.transfers) { transfer in
                    TransferRow(transfer: transfer)
                }
                .accessibilityLabel("transfers.table.label")
            }

            HStack {
                Button("transfers.clear_finished.button") {
                    vm.clearFinishedTransfers()
                    VoiceOver.announce(
                        String(localized: "transfers.clear_finished.announcement"),
                        category: .result
                    )
                }
                .disabled(!vm.transfers.contains(where: { !$0.state.isActive }))
                .help("transfers.clear_finished.hint")

                Spacer()

                Button("transfers.cancel.button", role: .destructive) {
                    cancelActiveTransfers()
                    VoiceOver.announce(
                        String(localized: "transfers.cancel.announcement"),
                        category: .progress
                    )
                }
                .disabled(!vm.hasActiveTransfers)
                .help("transfers.cancel.hint")

                Button("common.button.close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 580, minHeight: 360)
        .task { focusHeading = true }
    }
}

private struct TransferRow: View {
    let transfer: FileTransferRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(transfer.name, systemImage: transfer.direction.systemImage)
                Spacer()
                Text(transfer.state.label)
                    .foregroundStyle(transfer.state.isFailure ? .red : .secondary)
            }

            if let fraction = transfer.progress?.fractionCompleted {
                ProgressView(value: fraction)
                    .accessibilityLabel(progressAccessibilityLabel)
                    .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
            } else if transfer.state == .running {
                ProgressView()
                    .accessibilityLabel(progressAccessibilityLabel)
            }

            if let progress = transfer.progress {
                Text(progressLabel(progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = transfer.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel(String(localized: "transfers.error", defaultValue: "Error: \(message)"))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var progressAccessibilityLabel: String {
        switch transfer.direction {
        case .upload:
            String(localized: "transfers.upload.progress.label", defaultValue: "Upload progress for \(transfer.name)")
        case .download:
            String(localized: "transfers.download.progress.label", defaultValue: "Download progress for \(transfer.name)")
        }
    }

    private func progressLabel(_ progress: DSMTransferProgress) -> String {
        let completed = progress.completedBytes.formatted(.byteCount(style: .file))
        guard let total = progress.totalBytes else { return completed }
        return String(localized: "common.format.value_of_total", defaultValue: "\(completed) of \(total.formatted(.byteCount(style: .file)))")
    }
}

private extension FileTransferDirection {
    var systemImage: String {
        switch self {
        case .upload: "arrow.up.circle"
        case .download: "arrow.down.circle"
        }
    }
}

private extension FileTransferState {
    var isActive: Bool {
        self == .queued || self == .running
    }

    var isFailure: Bool {
        if case .failed = self { true } else { false }
    }

    var label: String {
        switch self {
        case .queued: String(localized: "common.status.waiting")
        case .running: String(localized: "common.status.in_progress")
        case .completed: String(localized: "common.status.done")
        case .cancelled: String(localized: "transfers.status.cancelled")
        case .failed: String(localized: "common.status.failed")
        }
    }
}
