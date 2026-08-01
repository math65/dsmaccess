//
//  AdvancedFileSearchSheet.swift
//  dsmaccess
//
//  File Station search using the criteria published by Synology.
//

import Foundation
import SwiftUI

struct AdvancedFileSearchDraft {
    var pattern = ""
    var extensions = ""
    var recursive = true
    var itemType = FileStationItemType.all
    var minimumSize = ""
    var maximumSize = ""
    var filtersModifiedDate = false
    var modifiedAfter = Date.now.addingTimeInterval(-2_592_000)
    var modifiedBefore = Date.now
    var filtersCreatedDate = false
    var createdAfter = Date.now.addingTimeInterval(-2_592_000)
    var createdBefore = Date.now
    var filtersAccessedDate = false
    var accessedAfter = Date.now.addingTimeInterval(-2_592_000)
    var accessedBefore = Date.now
    var owner = ""
    var group = ""

    func criteria(folderPath: String) throws -> FileStationSearchCriteria {
        let minimum = try byteCount(minimumSize, error: .invalidMinimumSize)
        let maximum = try byteCount(maximumSize, error: .invalidMaximumSize)
        if let minimum, let maximum, minimum > maximum {
            throw AdvancedFileSearchValidationError.invalidSizeRange
        }
        if filtersModifiedDate, modifiedAfter > modifiedBefore {
            throw AdvancedFileSearchValidationError.invalidModifiedDateRange
        }
        if filtersCreatedDate, createdAfter > createdBefore {
            throw AdvancedFileSearchValidationError.invalidCreatedDateRange
        }
        if filtersAccessedDate, accessedAfter > accessedBefore {
            throw AdvancedFileSearchValidationError.invalidAccessedDateRange
        }

        return FileStationSearchCriteria(
            folderPaths: [folderPath],
            recursive: recursive,
            pattern: nonempty(pattern),
            extensions: normalizedExtensions,
            itemType: itemType,
            minimumSize: minimum,
            maximumSize: maximum,
            modifiedAfter: filtersModifiedDate ? modifiedAfter : nil,
            modifiedBefore: filtersModifiedDate ? modifiedBefore : nil,
            createdAfter: filtersCreatedDate ? createdAfter : nil,
            createdBefore: filtersCreatedDate ? createdBefore : nil,
            accessedAfter: filtersAccessedDate ? accessedAfter : nil,
            accessedBefore: filtersAccessedDate ? accessedBefore : nil,
            owner: nonempty(owner),
            group: nonempty(group)
        )
    }

    private var normalizedExtensions: String? {
        let components = extensions
            .components(separatedBy: CharacterSet(charactersIn: ",; \t\n"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
            .filter { !$0.isEmpty }
        return components.isEmpty ? nil : components.joined(separator: ",")
    }

    private func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func byteCount(
        _ value: String,
        error: AdvancedFileSearchValidationError
    ) throws -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let result = try? Int64(trimmed, format: .number), result >= 0 else {
            throw error
        }
        return result
    }
}

enum AdvancedFileSearchValidationError: LocalizedError {
    case invalidMinimumSize
    case invalidMaximumSize
    case invalidSizeRange
    case invalidModifiedDateRange
    case invalidCreatedDateRange
    case invalidAccessedDateRange

    var errorDescription: String? {
        switch self {
        case .invalidMinimumSize:
            String(localized: "files.search.min_size.error")
        case .invalidMaximumSize:
            String(localized: "files.search.max_size.error")
        case .invalidSizeRange:
            String(localized: "files.search.size_range.error")
        case .invalidModifiedDateRange:
            String(localized: "files.search.modified_range.error")
        case .invalidCreatedDateRange:
            String(localized: "files.search.created_range.error")
        case .invalidAccessedDateRange:
            String(localized: "files.search.accessed_range.error")
        }
    }
}

struct AdvancedFileSearchSheet: View {
    let folderPath: String
    let onSubmit: (FileStationSearchCriteria) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = AdvancedFileSearchDraft()
    @State private var validationMessage: String?
    @AccessibilityFocusState private var focusTitle: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("files.search.advanced.title")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            Divider()

            Form {
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.readableRed)
                            .accessibilityFocused($focusError)
                    }
                }

                Section("common.column.location") {
                    LabeledContent("common.value.folder", value: folderPath)
                    Toggle("files.search.include_subfolders", isOn: $draft.recursive)
                }

                Section("files.search.name_and_type.section") {
                    TextField("files.search.name_pattern.label", text: $draft.pattern, prompt: Text("files.search.field.optional"))
                        .help("files.search.name_pattern.hint")
                    TextField(
                        "files.search.extensions.label",
                        text: $draft.extensions,
                        prompt: Text("pdf, docx, jpg")
                    )
                    .help("files.search.extensions.hint")
                    Picker("files.search.item_type.label", selection: $draft.itemType) {
                        Text("common.filter.all").tag(FileStationItemType.all)
                        Text("common.module.files").tag(FileStationItemType.file)
                        Text("common.label.folders").tag(FileStationItemType.directory)
                    }
                }

                Section("common.column.size") {
                    TextField(
                        "files.search.min_size.label",
                        text: $draft.minimumSize,
                        prompt: Text("files.search.extensions.none")
                    )
                    TextField(
                        "files.search.max_size.label",
                        text: $draft.maximumSize,
                        prompt: Text("files.search.extensions.none")
                    )
                }

                dateSection(
                    title: "common.column.date_modified",
                    isEnabled: $draft.filtersModifiedDate,
                    after: $draft.modifiedAfter,
                    before: $draft.modifiedBefore
                )
                dateSection(
                    title: "common.column.creation_date",
                    isEnabled: $draft.filtersCreatedDate,
                    after: $draft.createdAfter,
                    before: $draft.createdBefore
                )
                dateSection(
                    title: "files.search.last_accessed.label",
                    isEnabled: $draft.filtersAccessedDate,
                    after: $draft.accessedAfter,
                    before: $draft.accessedBefore
                )

                Section("common.column.owner") {
                    TextField("common.column.user", text: $draft.owner, prompt: Text("common.filter.all"))
                    TextField("common.column.group", text: $draft.group, prompt: Text("common.filter.all"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("files.search.button.search", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 610, height: 690)
        .onAppear {
            focusTitle = true
            VoiceOver.announce(String(localized: "files.search.advanced.title"), category: .navigation)
        }
    }

    private func dateSection(
        title: LocalizedStringKey,
        isEnabled: Binding<Bool>,
        after: Binding<Date>,
        before: Binding<Date>
    ) -> some View {
        Section(title) {
            Toggle("files.search.date_range.enable", isOn: isEnabled)
            if isEnabled.wrappedValue {
                DatePicker("files.search.date_range.from", selection: after)
                DatePicker("files.search.date_range.to", selection: before)
            }
        }
    }

    private func submit() {
        do {
            let criteria = try draft.criteria(folderPath: folderPath)
            validationMessage = nil
            onSubmit(criteria)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
            focusError = true
            VoiceOver.announce(error.localizedDescription, category: .error, priority: .high)
        }
    }
}
