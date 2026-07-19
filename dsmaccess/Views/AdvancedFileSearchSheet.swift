//
//  AdvancedFileSearchSheet.swift
//  dsmaccess
//
//  Recherche File Station avec les critères publiés par Synology.
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
            String(localized: "Saisissez une taille minimale valide en octets.")
        case .invalidMaximumSize:
            String(localized: "Saisissez une taille maximale valide en octets.")
        case .invalidSizeRange:
            String(localized: "La taille minimale doit être inférieure ou égale à la taille maximale.")
        case .invalidModifiedDateRange:
            String(localized: "La date de modification de début doit précéder la date de fin.")
        case .invalidCreatedDateRange:
            String(localized: "La date de création de début doit précéder la date de fin.")
        case .invalidAccessedDateRange:
            String(localized: "La date de dernier accès de début doit précéder la date de fin.")
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
            Text("Recherche avancée")
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
                            .foregroundStyle(.red)
                            .accessibilityFocused($focusError)
                    }
                }

                Section("Emplacement") {
                    LabeledContent("Dossier", value: folderPath)
                    Toggle("Inclure les sous-dossiers", isOn: $draft.recursive)
                }

                Section("Nom et type") {
                    TextField("Nom ou motif", text: $draft.pattern, prompt: Text("Facultatif"))
                        .help("Utilisez les caractères génériques pris en charge par File Station")
                    TextField(
                        "Extensions",
                        text: $draft.extensions,
                        prompt: Text("pdf, docx, jpg")
                    )
                    .help("Séparez plusieurs extensions par une virgule")
                    Picker("Type d’élément", selection: $draft.itemType) {
                        Text("Tous").tag(FileStationItemType.all)
                        Text("Fichiers").tag(FileStationItemType.file)
                        Text("Dossiers").tag(FileStationItemType.directory)
                    }
                }

                Section("Taille") {
                    TextField(
                        "Taille minimale en octets",
                        text: $draft.minimumSize,
                        prompt: Text("Aucune")
                    )
                    TextField(
                        "Taille maximale en octets",
                        text: $draft.maximumSize,
                        prompt: Text("Aucune")
                    )
                }

                dateSection(
                    title: "Date de modification",
                    isEnabled: $draft.filtersModifiedDate,
                    after: $draft.modifiedAfter,
                    before: $draft.modifiedBefore
                )
                dateSection(
                    title: "Date de création",
                    isEnabled: $draft.filtersCreatedDate,
                    after: $draft.createdAfter,
                    before: $draft.createdBefore
                )
                dateSection(
                    title: "Date de dernier accès",
                    isEnabled: $draft.filtersAccessedDate,
                    after: $draft.accessedAfter,
                    before: $draft.accessedBefore
                )

                Section("Propriétaire") {
                    TextField("Utilisateur", text: $draft.owner, prompt: Text("Tous"))
                    TextField("Groupe", text: $draft.group, prompt: Text("Tous"))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Rechercher", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 610, height: 690)
        .onAppear {
            focusTitle = true
            VoiceOver.announce("Recherche avancée", category: .navigation)
        }
    }

    private func dateSection(
        title: LocalizedStringKey,
        isEnabled: Binding<Bool>,
        after: Binding<Date>,
        before: Binding<Date>
    ) -> some View {
        Section(title) {
            Toggle("Limiter cette date", isOn: isEnabled)
            if isEnabled.wrappedValue {
                DatePicker("Du", selection: after)
                DatePicker("Au", selection: before)
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
