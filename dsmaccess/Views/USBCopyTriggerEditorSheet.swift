//
//  USBCopyTriggerEditorSheet.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyTriggerEditorSheet: View {
    let task: USBCopyTask
    let onSave: (USBCopyTrigger) async -> DSMOperationOutcome

    @State private var trigger: USBCopyTrigger
    @State private var isSaving = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var headingFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        task: USBCopyTask,
        trigger: USBCopyTrigger,
        onSave: @escaping (USBCopyTrigger) async -> DSMOperationOutcome
    ) {
        self.task = task
        self.onSave = onSave
        _trigger = State(initialValue: trigger)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "usb_copy.trigger_editor.title", defaultValue: "Trigger for \(task.name)"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .padding()
            Form {
                Section("common.label.trigger") {
                    USBCopyScheduleFields(
                        trigger: $trigger,
                        showsRunWhenPlugIn: task.isDefaultTask != true,
                        showsSchedule: task.isDefaultTask != true
                    )
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
        .frame(minWidth: 560, minHeight: 580)
        .onAppear {
            headingFocused = true
            VoiceOver.announce(
                String(localized: "usb_copy.trigger_editor.title.edit", defaultValue: "Edit trigger for \(task.name)"),
                category: .navigation
            )
        }
    }

    private func save() async {
        guard validate() else { return }
        isSaving = true
        errorMessage = nil
        VoiceOver.announce(String(localized: "common.status.saving"), category: .progress)
        let outcome = await onSave(trigger)
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

    private func validate() -> Bool {
        if trigger.scheduleEnabled && !trigger.scheduleContent.hasSelectedWeekday {
            return failValidation(String(localized: "common.validation.no_run_day_selected"))
        }
        if trigger.scheduleEnabled && !trigger.scheduleContent.hasValidReferenceDate {
            return failValidation(String(localized: "common.validation.invalid_reference_date"))
        }
        return true
    }

    private func failValidation(_ message: String) -> Bool {
        errorMessage = message
        errorFocused = true
        VoiceOver.announce(message, category: .error, priority: .high)
        return false
    }
}
