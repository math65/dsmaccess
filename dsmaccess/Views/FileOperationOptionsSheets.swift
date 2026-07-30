//
//  FileOperationOptionsSheets.swift
//  dsmaccess
//
//  Explicit options for File Station mutations liable to run into conflicts.
//

import SwiftUI

/// The title names the destination folder: selecting a folder is not enough to make it the
/// destination, it has to have been opened. Without that mention, a successful paste can
/// drop the items somewhere other than where the user believes they went.
struct FileConflictPolicySheet: View {
    let title: String
    let itemCount: Int
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

            LabeledContent("files.selection.items") { Text(itemCount, format: .number) }
                .labeledContentStyle(.readable)

            ConflictPolicyPicker(selection: $conflictPolicy)

            HStack {
                Button("common.button.cancel", role: .cancel) { dismiss() }
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
            Text("files.upload.options.title")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            Divider()

            Form {
                Section("files.selection.section") {
                    if fileCount > 0 {
                        LabeledContent("common.module.files") { Text(fileCount, format: .number) }
                    }
                    if folderCount > 0 {
                        LabeledContent("files.selection.folders") {
                            Text(folderCount, format: .number)
                        }
                    }
                }

                Section("files.conflict.section") {
                    ConflictPolicyPicker(selection: $conflictPolicy)
                }

                Section("common.label.folders") {
                    Toggle("files.upload.create_parents", isOn: $createsParentFolders)
                }

                Section("files.upload.dates.section") {
                    dateOption(
                        "files.upload.dates.set_modification",
                        isEnabled: $setsModificationDate,
                        date: $modificationDate
                    )
                    dateOption(
                        "files.upload.dates.set_creation",
                        isEnabled: $setsCreationDate,
                        date: $creationDate
                    )
                    dateOption(
                        "files.upload.dates.set_last_access",
                        isEnabled: $setsAccessDate,
                        date: $accessDate
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("common.button.upload", action: submit)
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
                DatePicker("files.upload.dates.mode.date_time", selection: date)
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
    @State private var usesCodepage = false
    @State private var codepage = FileStationArchiveCodepage.french
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
            Text("files.archive.create.title")
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

                Section("files.archive.section") {
                    TextField("files.archive.name.label", text: $archiveName)
                        .focused($nameIsFocused)
                    Picker("files.archive.format.label", selection: $format) {
                        Text("files.archive.format.zip").tag(FileStationArchiveFormat.zip)
                        Text("files.archive.format.7z").tag(FileStationArchiveFormat.sevenZip)
                    }
                    SecureField("common.field.optional_password", text: $password)
                    Toggle("files.extract.codepage.label", isOn: $usesCodepage)
                    if usesCodepage {
                        Picker("common.field.encoding", selection: $codepage) {
                            ForEach(FileStationArchiveCodepage.allCases) { value in
                                Text(value.localizedTitle).tag(value)
                            }
                        }
                    }
                }

                Section("common.operation.compression") {
                    Picker("common.column.level", selection: $level) {
                        ForEach(FileStationCompressionLevel.allCases, id: \.self) { value in
                            Text(value.localizedTitle).tag(value)
                        }
                    }
                    Picker("files.archive.mode.label", selection: $mode) {
                        ForEach(FileStationCompressionMode.allCases, id: \.self) { value in
                            Text(value.localizedTitle).tag(value)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("files.archive.create.button", action: submit)
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
            let message = String(localized: "files.archive.name.required.error")
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
                codepage: usesCodepage ? codepage : nil,
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
            Text(String(localized: "files.extract.title", defaultValue: "Extract \(archiveName)"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            Divider()

            Form {
                Section("files.conflict.section") {
                    ConflictPolicyPicker(selection: $conflictPolicy)
                }
                Section("common.label.organization") {
                    Toggle("files.upload.keep_structure", isOn: $keepsDirectoryStructure)
                    Toggle("files.extract.create_subfolder", isOn: $createsSubfolder)
                }
                Section("files.extract.codepage.section") {
                    SecureField("common.field.optional_password", text: $password)
                    Toggle("files.extract.codepage.label", isOn: $usesCodepage)
                    if usesCodepage {
                        Picker("common.field.encoding", selection: $codepage) {
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
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("common.button.extract", action: submit)
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
    var bytesPerSecond: Double?
    var timeRemaining: Duration?
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                Button("files.operation.cancel.button", role: .destructive, action: cancel)
                    .help("files.operation.cancel.button.hint")
            }

            if let fraction = progress?.normalizedFraction {
                ProgressView(value: fraction)
                    .accessibilityLabel(String(localized: "common.label.progress_for", defaultValue: "\(label) progress"))
                    .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
            } else {
                ProgressView()
                    .accessibilityLabel(String(localized: "files.operation.progress.title", defaultValue: "\(label) in progress…"))
            }

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .lineLimit(2)
            }

            // Throughput and time remaining are never announced: they change at every
            // sample and would drown out everything else. They stay readable on demand.
            if let throughput {
                Text(throughput)
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
            }
        }
        .padding(12)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var throughput: String? {
        guard let bytesPerSecond else { return nil }
        let speed = Int64(bytesPerSecond).formatted(.byteCount(style: .file))
        guard let timeRemaining else {
            return String(localized: "common.unit.per_second", defaultValue: "\(speed)/s")
        }
        // Under a minute, announcing seconds ticking by helps nobody; saying the end is
        // near does.
        guard timeRemaining >= .seconds(60) else {
            return String(localized: "files.operation.progress.remaining_under_minute", defaultValue: "\(speed)/s, less than a minute left")
        }
        let left = timeRemaining.formatted(
            .units(allowed: [.hours, .minutes], width: .wide, maximumUnitCount: 2)
        )
        return String(localized: "files.operation.progress.remaining", defaultValue: "\(speed)/s, about \(left) left")
    }

    private var detail: String? {
        if let processed = progress?.processedSize, let total = progress?.totalSize, total > 0 {
            return String(
                localized: "common.format.value_of_total",
                defaultValue: "\(processed.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))"
            )
        }
        if let processed = progress?.processedItemCount, let total = progress?.totalItemCount {
            return String(localized: "files.operation.progress.items", defaultValue: "\(processed) of \(total) items")
        }
        return progress?.currentPath
    }
}

/// The result of a long operation cannot rest on the VoiceOver announcement alone: emitted
/// while the app is in the background, it is never heard. The banner stays on screen until
/// the user hides it or changes folder.
struct FileOperationSummaryBanner: View {
    let summary: FileBrowserViewModel.OperationSummary
    let showBackgroundTasks: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(summary.message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            if summary.continuesInBackground {
                Button("common.action.file_station_tasks", action: showBackgroundTasks)
                    .help("common.action.file_station_tasks.hint")
            }
            Button("files.operation.result.hide.button", action: dismiss)
                .help("files.operation.result.hide.button.hint")
        }
        .padding(12)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("files.operation.result.title")
    }
}

private struct ConflictPolicyPicker: View {
    @Binding var selection: FileConflictPolicy

    var body: some View {
        Picker("files.conflict.mode.label", selection: $selection) {
            Text("files.conflict.mode.keep").tag(FileConflictPolicy.skip)
            Text("files.conflict.mode.replace").tag(FileConflictPolicy.overwrite)
        }
        Text(selection == .skip
             ? "files.conflict.keep.description"
             : "files.conflict.replace.description")
            .font(.callout)
            .foregroundStyle(selection == .overwrite ? .red : .secondary)
    }
}

private extension FileStationCompressionLevel {
    var localizedTitle: String {
        switch self {
        case .moderate: String(localized: "files.archive.level.balanced")
        case .store: String(localized: "files.archive.level.none")
        case .fastest: String(localized: "files.archive.level.fastest")
        case .best: String(localized: "files.archive.level.best")
        }
    }
}

private extension FileStationCompressionMode {
    var localizedTitle: String {
        switch self {
        case .add: String(localized: "files.archive.update_mode.add_replace")
        case .update: String(localized: "common.button.update")
        case .refreshen: String(localized: "files.archive.update_mode.refresh")
        case .synchronize: String(localized: "files.archive.update_mode.synchronize")
        }
    }
}

extension FileStationArchiveCodepage {
    var localizedTitle: String {
        switch self {
        case .english: String(localized: "files.extract.codepage.english")
        case .traditionalChinese: String(localized: "files.extract.codepage.traditional_chinese")
        case .simplifiedChinese: String(localized: "files.extract.codepage.simplified_chinese")
        case .korean: String(localized: "files.extract.codepage.korean")
        case .german: String(localized: "files.extract.codepage.german")
        case .french: String(localized: "files.extract.codepage.french")
        case .italian: String(localized: "files.extract.codepage.italian")
        case .spanish: String(localized: "files.extract.codepage.spanish")
        case .japanese: String(localized: "files.extract.codepage.japanese")
        case .danish: String(localized: "files.extract.codepage.danish")
        case .norwegian: String(localized: "files.extract.codepage.norwegian")
        case .swedish: String(localized: "files.extract.codepage.swedish")
        case .dutch: String(localized: "files.extract.codepage.dutch")
        case .russian: String(localized: "files.extract.codepage.russian")
        case .polish: String(localized: "files.extract.codepage.polish")
        case .brazilianPortuguese: String(localized: "files.extract.codepage.brazilian_portuguese")
        case .portuguese: String(localized: "files.extract.codepage.portuguese")
        case .hungarian: String(localized: "files.extract.codepage.hungarian")
        case .turkish: String(localized: "files.extract.codepage.turkish")
        case .czech: String(localized: "files.extract.codepage.czech")
        }
    }
}
