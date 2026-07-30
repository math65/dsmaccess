//
//  USBCopyFilterFields.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyFilterFields: View {
    @Binding var selection: USBCopyFilterSelection
    @State private var newRule = ""
    @State private var validationMessage: String?
    @AccessibilityFocusState private var validationFocused: Bool

    var body: some View {
        Toggle("usb_copy.filter.include_others.label", isOn: $selection.includesOtherFiles)
            .help("usb_copy.filter.include_others.description")

        ForEach(USBCopyFileCategory.allCases) { category in
            DisclosureGroup(category.localizedName) {
                VStack(alignment: .leading) {
                    Toggle(String(localized: "usb_copy.filter.category.include_all.action", defaultValue: "Include everything in \(category.localizedName)"), isOn: categoryBinding(category))
                    Divider()
                    ForEach(category.extensions.sorted(), id: \.self) { fileExtension in
                        Toggle(String(localized: "usb_copy.filter.rule.extension_pattern", defaultValue: "*.\(fileExtension)"), isOn: extensionBinding(fileExtension))
                    }
                }
                .padding(.leading)
            }
        }

        GroupBox("usb_copy.filter.custom_rules.title") {
            VStack(alignment: .leading) {
                Text("usb_copy.filter.custom_rules.hint")
                    .foregroundStyle(.readableSecondary)
                HStack {
                    TextField("usb_copy.filter.rule.placeholder", text: $newRule)
                        .onSubmit(addRule)
                        .help("usb_copy.filter.rule.field.label")
                    Button("common.button.add", action: addRule)
                        .disabled(trimmedRule.isEmpty)
                        .help("usb_copy.filter.rule.add.action")
                }

                if let validationMessage {
                    Label(validationMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.readableRed)
                        .accessibilityFocused($validationFocused)
                }

                ForEach(selection.customExtensions, id: \.self) { fileExtension in
                    customRuleRow("*.\(fileExtension)") {
                        selection.customExtensions.removeAll { $0 == fileExtension }
                    }
                }
                ForEach(selection.customNames, id: \.self) { name in
                    customRuleRow(name) {
                        selection.customNames.removeAll { $0 == name }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func customRuleRow(_ rule: String, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(rule)
            Spacer()
            Button(String(localized: "usb_copy.filter.rule.remove.action", defaultValue: "Remove \(rule)"), systemImage: "minus.circle", action: remove)
                .labelStyle(.iconOnly)
                .help(String(localized: "usb_copy.filter.rule.remove.label", defaultValue: "Remove the \(rule) rule"))
        }
    }

    private func categoryBinding(_ category: USBCopyFileCategory) -> Binding<Bool> {
        Binding(
            get: { category.extensions.isSubset(of: selection.selectedExtensions) },
            set: { isSelected in
                if isSelected {
                    selection.selectedExtensions.formUnion(category.extensions)
                } else {
                    selection.selectedExtensions.subtract(category.extensions)
                }
            }
        )
    }

    private func extensionBinding(_ fileExtension: String) -> Binding<Bool> {
        Binding(
            get: { selection.selectedExtensions.contains(fileExtension) },
            set: { isSelected in
                if isSelected {
                    selection.selectedExtensions.insert(fileExtension)
                } else {
                    selection.selectedExtensions.remove(fileExtension)
                }
            }
        )
    }

    private var trimmedRule: String {
        newRule.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addRule() {
        let value = trimmedRule
        guard !value.isEmpty else { return }
        let forbidden = CharacterSet(charactersIn: ":?\"<>|\\/")
        guard value.rangeOfCharacter(from: forbidden) == nil else {
            showValidation(String(localized: "usb_copy.filter.rule.invalid_character.error"))
            return
        }

        if value.hasPrefix("*.") {
            let fileExtension = String(value.dropFirst(2)).lowercased()
            guard !fileExtension.isEmpty, !fileExtension.contains("*") else {
                showValidation(String(localized: "usb_copy.filter.rule.missing_extension.error"))
                return
            }
            if !selection.customExtensions.contains(fileExtension) {
                selection.customExtensions.append(fileExtension)
                selection.customExtensions.sort()
            }
        } else {
            guard !value.contains("*") else {
                showValidation(String(localized: "usb_copy.filter.rule.extension_format.error"))
                return
            }
            if !selection.customNames.contains(value) {
                selection.customNames.append(value)
                selection.customNames.sort()
            }
        }
        newRule = ""
        validationMessage = nil
    }

    private func showValidation(_ message: String) {
        validationMessage = message
        validationFocused = true
        VoiceOver.announce(message, category: .error, priority: .high)
    }
}
