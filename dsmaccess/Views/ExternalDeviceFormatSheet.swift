//
//  ExternalDeviceFormatSheet.swift
//  dsmaccess
//
//  Choice of file system before formatting an external device.
//

import SwiftUI

struct ExternalDeviceFormatSheet: View {
    let device: ExternalStorageDevice
    let format: (ExternalStorageFileSystem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fileSystem: ExternalStorageFileSystem = .fat
    @State private var isConfirming = false
    @AccessibilityFocusState private var focusesWarning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(
                String(
                    localized: "external_devices.format.sheet.title",
                    defaultValue: "Format \(device.displayName)"
                )
            )
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)

            Text(
                String(
                    localized: "external_devices.format.warning",
                    defaultValue: "Everything on \(device.displayName) will be erased, including all of its partitions. This cannot be undone."
                )
            )
            .foregroundStyle(.readableRed)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityFocused($focusesWarning)

            Picker("external_devices.format.filesystem.label", selection: $fileSystem) {
                ForEach(ExternalStorageFileSystem.allCases) { candidate in
                    Text(candidate.title).tag(candidate)
                }
            }
            .pickerStyle(.radioGroup)

            Text(fileSystem.explanation)
                .font(.caption)
                .foregroundStyle(.readableSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("external_devices.action.format", role: .destructive) {
                    isConfirming = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .task { focusesWarning = true }
        .confirmationDialog(
            String(
                localized: "external_devices.format.confirm.title",
                defaultValue: "Erase \(device.displayName)?"
            ),
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("external_devices.format.confirm.button", role: .destructive) {
                format(fileSystem)
                dismiss()
            }
            Button("common.button.cancel", role: .cancel) { }
        } message: {
            Text(
                String(
                    localized: "external_devices.format.confirm.message",
                    defaultValue: "\(device.displayName) will be erased and formatted in \(fileSystem.title). This cannot be undone."
                )
            )
        }
    }
}
