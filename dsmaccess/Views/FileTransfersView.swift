//
//  FileTransfersView.swift
//  dsmaccess
//
//  Accessible queue of File Station transfers.
//

import SwiftUI

struct FileTransfersView: View {
    @Bindable var vm: FileBrowserViewModel
    let cancelActiveTransfers: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusHeading: Bool
    @State private var order = [KeyPathComparator(\FileTransferRecord.name, order: .forward)]

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
                Table(vm.transfers.sorted(using: order), sortOrder: $order) {
                    TableColumn("common.column.name", value: \.name) { transfer in
                        Text(transfer.name)
                    }
                    TableColumn("common.column.direction", value: \.sortableDirection) { transfer in
                        Text(transfer.directionDescription)
                    }
                    TableColumn("common.column.state", value: \.sortableStatus) { transfer in
                        Text(transfer.statusDescription)
                            .foregroundStyle(transfer.state.isFailure ? .readableRed : .readableSecondary)
                    }
                    TableColumn("common.column.progress", value: \.sortableProgress) { transfer in
                        Text(transfer.progressDescription)
                    }
                    TableColumn("transfers.column.transferred", value: \.sortableTransferred) { transfer in
                        Text(transfer.transferredDescription)
                    }
                    TableColumn("common.column.message", value: \.sortableMessage) { transfer in
                        Text(transfer.state.failureMessage ?? "—")
                    }
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
        .frame(minWidth: 760, minHeight: 360)
        .task { focusHeading = true }
    }
}
