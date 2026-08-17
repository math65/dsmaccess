//
//  PackageUninstallSheet.swift
//  dsmaccess
//
//  The questions a package asks before being removed, rebuilt as native controls from what
//  DSM serves in `uninstall_pages`.
//

import SwiftUI

struct PackageUninstallRequest: Identifiable {
    let id = UUID()
    let package: PackageInfo
    let wizard: PackageUninstallWizard
}

struct PackageUninstallSheet: View {
    let request: PackageUninstallRequest
    let confirm: ([String: Bool]) -> Void

    @State private var answers: [String: Bool]
    @AccessibilityFocusState private var focusHeading: Bool
    @Environment(\.dismiss) private var dismiss

    init(request: PackageUninstallRequest, confirm: @escaping ([String: Bool]) -> Void) {
        self.request = request
        self.confirm = confirm
        _answers = State(initialValue: request.wizard.defaultAnswers)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)
            Divider()
            Form {
                ForEach(request.wizard.steps) { step in
                    Section {
                        ForEach(step.explanations, id: \.self) { explanation in
                            Text(explanation)
                        }
                        ForEach(step.fields) { field in
                            fieldView(field)
                        }
                    } header: {
                        if let title = step.title {
                            Text(title)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("packages.uninstall.wizard.label")
            Divider()
            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(uninstallTitle, role: .destructive) {
                    confirm(answers)
                    dismiss()
                }
            }
            .padding()
        }
        .frame(width: 560, height: 460)
        .onAppear {
            focusHeading = true
            VoiceOver.announce(title, category: .navigation)
        }
    }

    @ViewBuilder
    private func fieldView(_ field: PackageUninstallWizard.Field) -> some View {
        switch field.kind {
        case .singleChoice:
            Picker(selection: singleChoiceBinding(field)) {
                ForEach(field.options) { option in
                    Text(option.label).tag(option.key)
                }
            } label: {
                Text(field.prompt ?? String(localized: "packages.uninstall.wizard.choice"))
            }
            .pickerStyle(.radioGroup)
        case .multipleChoice:
            if let prompt = field.prompt {
                Text(prompt)
            }
            ForEach(field.options) { option in
                Toggle(option.label, isOn: multipleChoiceBinding(option.key))
            }
        }
    }

    /// A single-choice field is one key true and the others false: DSM expects every key of
    /// the group in the answers, not only the chosen one.
    private func singleChoiceBinding(
        _ field: PackageUninstallWizard.Field
    ) -> Binding<String> {
        Binding(
            get: {
                field.options.first { answers[$0.key] == true }?.key
                    ?? field.options.first?.key
                    ?? ""
            },
            set: { chosen in
                for option in field.options {
                    answers[option.key] = option.key == chosen
                }
            }
        )
    }

    private func multipleChoiceBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { answers[key] ?? false },
            set: { answers[key] = $0 }
        )
    }

    private var title: String {
        String(
            localized: "packages.uninstall.wizard.title",
            defaultValue: "Uninstall \(request.package.displayName)"
        )
    }

    private var uninstallTitle: String {
        String(
            localized: "packages.uninstall.action",
            defaultValue: "Uninstall \(request.package.displayName)"
        )
    }
}
