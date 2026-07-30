//
//  USBCopyFilterEditorSheet.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyFilterEditorSheet: View {
    let task: USBCopyTask
    let onSave: (USBCopyFilter) async -> DSMOperationOutcome

    @State private var selection: USBCopyFilterSelection
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var headingFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        task: USBCopyTask,
        filter: USBCopyFilter,
        onSave: @escaping (USBCopyFilter) async -> DSMOperationOutcome
    ) {
        self.task = task
        self.onSave = onSave
        _selection = State(initialValue: USBCopyFilterSelection(filter: filter))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "usb_copy.filter.sheet.title", defaultValue: "File filter for \(task.name)"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .padding()
            Form {
                Section("usb_copy.filter.file_types.title") {
                    USBCopyFilterFields(selection: $selection)
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
            Divider()
            HStack {
                if isSaving { ProgressView("common.status.saving").controlSize(.small) }
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("common.button.save") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
            .padding()
        }
        .frame(minWidth: 620, minHeight: 680)
        .onAppear {
            headingFocused = true
            VoiceOver.announce(
                String(localized: "usb_copy.filter.edit.action", defaultValue: "Edit file filter for \(task.name)"),
                category: .navigation
            )
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        VoiceOver.announce(String(localized: "common.status.saving"), category: .progress)
        let outcome = await onSave(selection.filter)
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
