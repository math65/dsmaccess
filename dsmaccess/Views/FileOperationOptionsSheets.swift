//
//  FileOperationOptionsSheets.swift
//  dsmaccess
//
//  Explicit options for File Station mutations liable to run into conflicts.
//

import SwiftUI

/// Shown only when a name already exists at the destination — an upload or a paste that
/// collides with nothing goes straight through. The title names the destination folder:
/// selecting a folder is not enough to make it the destination, it has to have been opened.
/// Without that mention, a successful paste can drop the items somewhere other than where the
/// user believes they went.
struct FileConflictPolicySheet: View {
    let title: String
    /// What the destination already holds. Naming them is the point: "3 items" says nothing
    /// about what is at stake, "budget.xlsx" says everything.
    let conflictingNames: [String]
    let confirmLabel: LocalizedStringKey
    let onSubmit: (FileConflictPolicy) -> Void

    private static let namesShown = 3

    @Environment(\.dismiss) private var dismiss
    @State private var conflictPolicy = FileConflictPolicy.skip
    @AccessibilityFocusState private var focusTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            Text(conflictSummary)
                .fixedSize(horizontal: false, vertical: true)

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

    private var conflictSummary: String {
        guard conflictingNames.count > Self.namesShown else {
            let names = conflictingNames.formatted(.list(type: .and))
            return conflictingNames.count == 1
                ? String(localized: "files.conflict.existing.one", defaultValue: "\(names) already exists in this folder.")
                : String(localized: "files.conflict.existing.some", defaultValue: "\(names) already exist in this folder.")
        }
        let shown = conflictingNames.prefix(Self.namesShown).formatted(.list(type: .and))
        let others = conflictingNames.count - Self.namesShown
        return String(
            localized: "files.conflict.existing.many",
            defaultValue: "\(shown) and \(others) other items already exist in this folder."
        )
    }
}

struct FileCompressionOptionsSheet: View {
    let initialName: String
    let defaultCodepage: FileStationArchiveCodepage
    let onSubmit: (String, FileStationCompressionOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var archiveName: String
    @State private var format = FileStationArchiveFormat.zip
    @State private var level = FileStationCompressionLevel.moderate
    @State private var mode = FileStationCompressionMode.add
    @State private var usesCodepage = false
    @State private var codepage: FileStationArchiveCodepage
    @State private var password = ""
    @State private var validationMessage: String?
    @FocusState private var nameIsFocused: Bool
    @AccessibilityFocusState private var focusError: Bool

    init(
        initialName: String,
        defaultCodepage: FileStationArchiveCodepage,
        onSubmit: @escaping (String, FileStationCompressionOptions) -> Void
    ) {
        self.initialName = initialName
        self.defaultCodepage = defaultCodepage
        self.onSubmit = onSubmit
        _archiveName = State(initialValue: initialName)
        _codepage = State(initialValue: defaultCodepage)
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
                            .foregroundStyle(.readableRed)
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
            .accessibilityLabel("files.compression.options.label")

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
            VoiceOver.announce(String(localized: "files.archive.create.title"), category: .navigation)
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
    let defaultCodepage: FileStationArchiveCodepage
    let onSubmit: (FileStationExtractionOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var conflictPolicy = FileConflictPolicy.skip
    @State private var keepsDirectoryStructure = true
    @State private var createsSubfolder = true
    @State private var usesCodepage = false
    @State private var codepage: FileStationArchiveCodepage
    @State private var password = ""
    @AccessibilityFocusState private var focusTitle: Bool

    init(
        archiveName: String,
        itemIDs: [Int],
        defaultCodepage: FileStationArchiveCodepage,
        initialCodepage: FileStationArchiveCodepage? = nil,
        initialPassword: String = "",
        onSubmit: @escaping (FileStationExtractionOptions) -> Void
    ) {
        self.archiveName = archiveName
        self.itemIDs = itemIDs
        self.defaultCodepage = defaultCodepage
        self.onSubmit = onSubmit
        _usesCodepage = State(initialValue: initialCodepage != nil)
        _codepage = State(initialValue: initialCodepage ?? defaultCodepage)
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
            .accessibilityLabel("files.extraction.options.label")

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
    let progress: FileProgressDisplay?
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
