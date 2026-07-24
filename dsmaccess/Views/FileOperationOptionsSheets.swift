//
//  FileOperationOptionsSheets.swift
//  dsmaccess
//
//  Options explicites pour les mutations File Station susceptibles de rencontrer des conflits.
//

import SwiftUI

struct FileConflictPolicySheet: View {
    let title: LocalizedStringKey
    let confirmLabel: LocalizedStringKey
    let onSubmit: (FileConflictPolicy) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var conflictPolicy = FileConflictPolicy.skip
    @AccessibilityFocusState private var focusTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            ConflictPolicyPicker(selection: $conflictPolicy)

            HStack {
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(confirmLabel) {
                    onSubmit(conflictPolicy)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { focusTitle = true }
    }
}

struct FileUploadOptionsSheet: View {
    let fileCount: Int
    var folderCount = 0
    let onSubmit: (FileStationUploadOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var conflictPolicy = FileConflictPolicy.skip
    @State private var createsParentFolders = true
    @State private var setsModificationDate = false
    @State private var modificationDate = Date.now
    @State private var setsCreationDate = false
    @State private var creationDate = Date.now
    @State private var setsAccessDate = false
    @State private var accessDate = Date.now
    @AccessibilityFocusState private var focusTitle: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Options d’envoi")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            Divider()

            Form {
                Section("Éléments sélectionnés") {
                    if fileCount > 0 {
                        LabeledContent("Fichiers") { Text(fileCount, format: .number) }
                    }
                    if folderCount > 0 {
                        LabeledContent("Dossiers (contenu inclus)") {
                            Text(folderCount, format: .number)
                        }
                    }
                }

                Section("Conflits de noms") {
                    ConflictPolicyPicker(selection: $conflictPolicy)
                }

                Section("Dossiers") {
                    Toggle("Créer les dossiers parents manquants", isOn: $createsParentFolders)
                }

                Section("Dates appliquées aux fichiers envoyés") {
                    dateOption(
                        "Définir la date de modification",
                        isEnabled: $setsModificationDate,
                        date: $modificationDate
                    )
                    dateOption(
                        "Définir la date de création",
                        isEnabled: $setsCreationDate,
                        date: $creationDate
                    )
                    dateOption(
                        "Définir la date de dernier accès",
                        isEnabled: $setsAccessDate,
                        date: $accessDate
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Envoyer", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 550, height: 560)
        .onAppear { focusTitle = true }
    }

    private func dateOption(
        _ title: LocalizedStringKey,
        isEnabled: Binding<Bool>,
        date: Binding<Date>
    ) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: isEnabled)
            if isEnabled.wrappedValue {
                DatePicker("Date et heure", selection: date)
                    .padding(.leading, 20)
            }
        }
    }

    private func submit() {
        onSubmit(
            FileStationUploadOptions(
                conflictPolicy: conflictPolicy,
                createParentFolders: createsParentFolders,
                modificationDate: setsModificationDate ? modificationDate : nil,
                creationDate: setsCreationDate ? creationDate : nil,
                accessDate: setsAccessDate ? accessDate : nil
            )
        )
        dismiss()
    }
}

struct FileCompressionOptionsSheet: View {
    let initialName: String
    let onSubmit: (String, FileStationCompressionOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var archiveName: String
    @State private var format = FileStationArchiveFormat.zip
    @State private var level = FileStationCompressionLevel.moderate
    @State private var mode = FileStationCompressionMode.add
    @State private var password = ""
    @State private var validationMessage: String?
    @FocusState private var nameIsFocused: Bool
    @AccessibilityFocusState private var focusError: Bool

    init(
        initialName: String,
        onSubmit: @escaping (String, FileStationCompressionOptions) -> Void
    ) {
        self.initialName = initialName
        self.onSubmit = onSubmit
        _archiveName = State(initialValue: initialName)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Créer une archive")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)

            Divider()

            Form {
                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityFocused($focusError)
                    }
                }

                Section("Archive") {
                    TextField("Nom de l’archive", text: $archiveName)
                        .focused($nameIsFocused)
                    Picker("Format", selection: $format) {
                        Text("ZIP").tag(FileStationArchiveFormat.zip)
                        Text("7z").tag(FileStationArchiveFormat.sevenZip)
                    }
                    SecureField("Mot de passe facultatif", text: $password)
                }

                Section("Compression") {
                    Picker("Niveau", selection: $level) {
                        ForEach(FileStationCompressionLevel.allCases, id: \.self) { value in
                            Text(value.localizedTitle).tag(value)
                        }
                    }
                    Picker("Mode", selection: $mode) {
                        ForEach(FileStationCompressionMode.allCases, id: \.self) { value in
                            Text(value.localizedTitle).tag(value)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Créer l’archive", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 460)
        .onAppear {
            nameIsFocused = true
            VoiceOver.announce("Créer une archive", category: .navigation)
        }
    }

    private func submit() {
        let trimmed = archiveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let message = String(localized: "Le nom de l’archive est requis.")
            validationMessage = message
            focusError = true
            VoiceOver.announce(message, category: .error, priority: .high)
            return
        }
        onSubmit(
            trimmed,
            FileStationCompressionOptions(
                level: level,
                mode: mode,
                format: format,
                password: password.isEmpty ? nil : password
            )
        )
        dismiss()
    }
}

struct FileExtractionOptionsSheet: View {
    let archiveName: String
    let itemIDs: [Int]
    let onSubmit: (FileStationExtractionOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var conflictPolicy = FileConflictPolicy.skip
    @State private var keepsDirectoryStructure = true
    @State private var createsSubfolder = true
    @State private var usesCodepage = false
    @State private var codepage = FileStationArchiveCodepage.french
    @State private var password = ""
    @AccessibilityFocusState private var focusTitle: Bool

    init(
        archiveName: String,
        itemIDs: [Int],
        initialCodepage: FileStationArchiveCodepage? = nil,
        initialPassword: String = "",
        onSubmit: @escaping (FileStationExtractionOptions) -> Void
    ) {
        self.archiveName = archiveName
        self.itemIDs = itemIDs
        self.onSubmit = onSubmit
        _usesCodepage = State(initialValue: initialCodepage != nil)
        _codepage = State(initialValue: initialCodepage ?? .french)
        _password = State(initialValue: initialPassword)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Extraire \(archiveName)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            Divider()

            Form {
                Section("Conflits de noms") {
                    ConflictPolicyPicker(selection: $conflictPolicy)
                }
                Section("Organisation") {
                    Toggle("Conserver la structure des dossiers", isOn: $keepsDirectoryStructure)
                    Toggle("Créer un sous-dossier pour l’archive", isOn: $createsSubfolder)
                }
                Section("Archive protégée ou ancienne") {
                    SecureField("Mot de passe facultatif", text: $password)
                    Toggle("Choisir l’encodage des noms", isOn: $usesCodepage)
                    if usesCodepage {
                        Picker("Encodage", selection: $codepage) {
                            ForEach(FileStationArchiveCodepage.allCases) { value in
                                Text(value.localizedTitle).tag(value)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Annuler", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Extraire", action: submit)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 540, height: 500)
        .onAppear { focusTitle = true }
    }

    private func submit() {
        onSubmit(
            FileStationExtractionOptions(
                conflictPolicy: conflictPolicy,
                keepsDirectoryStructure: keepsDirectoryStructure,
                createsSubfolder: createsSubfolder,
                codepage: usesCodepage ? codepage : nil,
                password: password.isEmpty ? nil : password,
                itemIDs: itemIDs
            )
        )
        dismiss()
    }
}

struct FileOperationProgressBanner: View {
    let label: String
    let progress: FileOperationProgress?
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Button("Annuler l’opération", role: .destructive, action: cancel)
                    .help("Arrêter l’opération en cours sur le NAS")
            }

            if let fraction = progress?.normalizedFraction {
                ProgressView(value: fraction)
                    .accessibilityLabel(String(localized: "Progression de \(label)"))
                    .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
            } else {
                ProgressView()
                    .accessibilityLabel(String(localized: "\(label) en cours…"))
            }

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var detail: String? {
        if let processed = progress?.processedSize, let total = progress?.totalSize, total > 0 {
            return String(
                localized: "\(processed.formatted(.byteCount(style: .file))) sur \(total.formatted(.byteCount(style: .file)))"
            )
        }
        if let processed = progress?.processedItemCount, let total = progress?.totalItemCount {
            return String(localized: "\(processed) sur \(total) éléments")
        }
        return progress?.currentPath
    }
}

private struct ConflictPolicyPicker: View {
    @Binding var selection: FileConflictPolicy

    var body: some View {
        Picker("Si un élément existe déjà", selection: $selection) {
            Text("Conserver l’élément existant").tag(FileConflictPolicy.skip)
            Text("Remplacer l’élément existant").tag(FileConflictPolicy.overwrite)
        }
        Text(selection == .skip
             ? "Les éléments en conflit ne seront pas modifiés."
             : "Les éléments existants portant le même nom seront remplacés.")
            .font(.callout)
            .foregroundStyle(selection == .overwrite ? .red : .secondary)
    }
}

private extension FileStationCompressionLevel {
    var localizedTitle: String {
        switch self {
        case .moderate: String(localized: "Équilibré")
        case .store: String(localized: "Sans compression")
        case .fastest: String(localized: "Le plus rapide")
        case .best: String(localized: "Meilleure compression")
        }
    }
}

private extension FileStationCompressionMode {
    var localizedTitle: String {
        switch self {
        case .add: String(localized: "Ajouter et remplacer")
        case .update: String(localized: "Mettre à jour")
        case .refreshen: String(localized: "Actualiser les fichiers existants")
        case .synchronize: String(localized: "Synchroniser le contenu")
        }
    }
}

extension FileStationArchiveCodepage {
    var localizedTitle: String {
        switch self {
        case .english: String(localized: "Anglais")
        case .traditionalChinese: String(localized: "Chinois traditionnel")
        case .simplifiedChinese: String(localized: "Chinois simplifié")
        case .korean: String(localized: "Coréen")
        case .german: String(localized: "Allemand")
        case .french: String(localized: "Français")
        case .italian: String(localized: "Italien")
        case .spanish: String(localized: "Espagnol")
        case .japanese: String(localized: "Japonais")
        case .danish: String(localized: "Danois")
        case .norwegian: String(localized: "Norvégien")
        case .swedish: String(localized: "Suédois")
        case .dutch: String(localized: "Néerlandais")
        case .russian: String(localized: "Russe")
        case .polish: String(localized: "Polonais")
        case .brazilianPortuguese: String(localized: "Portugais du Brésil")
        case .portuguese: String(localized: "Portugais")
        case .hungarian: String(localized: "Hongrois")
        case .turkish: String(localized: "Turc")
        case .czech: String(localized: "Tchèque")
        }
    }
}
