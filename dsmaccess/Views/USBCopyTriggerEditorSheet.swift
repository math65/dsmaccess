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
            Text("Déclenchement de \(task.name)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .padding()
            Form {
                Section("Déclenchement") {
                    USBCopyScheduleFields(
                        trigger: $trigger,
                        showsRunWhenPlugIn: task.isDefaultTask != true,
                        showsSchedule: task.isDefaultTask != true
                    )
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityFocused($errorFocused)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if isSaving { ProgressView("Enregistrement…").controlSize(.small) }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button("Enregistrer") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 580)
        .onAppear {
            headingFocused = true
            VoiceOver.announce(
                String(localized: "Modifier le déclenchement de \(task.name)"),
                category: .navigation
            )
        }
    }

    private func save() async {
        guard validate() else { return }
        isSaving = true
        errorMessage = nil
        VoiceOver.announce(String(localized: "Enregistrement…"), category: .progress)
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
            return failValidation(String(localized: "Choisissez au moins un jour d’exécution."))
        }
        if trigger.scheduleEnabled && !trigger.scheduleContent.hasValidReferenceDate {
            return failValidation(String(localized: "Saisissez une date de référence valide au format AAAA/MM/JJ."))
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
