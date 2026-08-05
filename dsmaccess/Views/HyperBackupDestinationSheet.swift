//
//  HyperBackupDestinationSheet.swift
//  dsmaccess
//
//  Choosing where a restore puts its copy, and whether it may replace anything.
//

import SwiftUI

struct HyperBackupDestinationSheet: View {
    let entries: [HyperBackupEntry]
    let shareNames: [String]
    let isRestoring: Bool
    let loadFolders: (String) async throws -> [FileStationItem]
    let createFolder: (String, String) async throws -> Void
    /// Returns whether the restore succeeded, so the sheet only closes on success and an
    /// error stays readable where it happened.
    let restore: (String, Bool) async -> Bool

    @State private var destinationPath = ""
    @State private var replacesExisting = false
    @State private var showsFolderPicker = false
    @AccessibilityFocusState private var focusForm: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("hyper_backup.restore.destination.label") {
                        Text(verbatim: destinationPath)
                            .textSelection(.enabled)
                    }
                    .labeledContentStyle(.readable)

                    Button("hyper_backup.restore.destination.choose") {
                        showsFolderPicker = true
                    }
                    .accessibilityHint("hyper_backup.restore.destination.hint")

                    Toggle("hyper_backup.restore.replace.label", isOn: $replacesExisting)
                        .accessibilityHint("hyper_backup.restore.replace.hint")
                } header: {
                    Text("hyper_backup.restore.destination.section")
                } footer: {
                    Text(consequence)
                        .foregroundStyle(replacesExisting ? .readableOrange : .readableSecondary)
                }

                Section("hyper_backup.restore.selection.section") {
                    ForEach(entries) { entry in
                        LabeledContent(entry.name) { Text(entry.kindDescription) }
                            .labeledContentStyle(.readable)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("hyper_backup.restore.destination.form.label")
            .accessibilityFocused($focusForm)
            .navigationTitle("hyper_backup.restore.destination.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("hyper_backup.restore.restore.button") {
                        Task { await submit() }
                    }
                    .disabled(destinationPath.isEmpty || isRestoring)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.button.cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 460)
        .sheet(isPresented: $showsFolderPicker) {
            SharedFolderPickerSheet(
                initialPath: destinationPath,
                shareNames: shareNames,
                loadFolders: loadFolders,
                createFolder: createFolder
            ) { chosen in
                destinationPath = chosen
            }
        }
        .task {
            destinationPath = shareNames.first.map { "/\($0)" } ?? ""
            focusForm = true
        }
    }

    /// States the outcome plainly in both directions: the safe one is the default, and the
    /// destructive one names what it costs rather than only warning in colour.
    private var consequence: String {
        guard !destinationPath.isEmpty else {
            return String(localized: "hyper_backup.restore.consequence.none")
        }
        return replacesExisting
            ? String(localized: "hyper_backup.restore.consequence.replace", defaultValue: "Items of the same name already in \(destinationPath) will be replaced, and their current contents cannot be recovered.")
            : String(localized: "hyper_backup.restore.consequence.keep", defaultValue: "The originals are left untouched. If \(destinationPath) already holds items of the same name, nothing is restored and the app says so.")
    }

    private func submit() async {
        guard !destinationPath.isEmpty else { return }
        if await restore(destinationPath, replacesExisting) {
            dismiss()
        }
    }
}
