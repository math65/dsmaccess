//
//  USBCopyTaskEditorSheet.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyTaskEditorSheet: View {
    private let task: USBCopyTask?
    private let localShares: [SharedFolder]
    private let externalShares: [SharedFolder]
    private let loadFolders: (String) async throws -> [FileStationItem]
    private let onCreate: ((USBCopyTaskCreation) async -> DSMOperationOutcome)?
    private let onSave: ((USBCopyTaskSettings) async -> DSMOperationOutcome)?

    @State private var type: USBCopyTaskType
    @State private var name: String
    @State private var sourcePath: String
    @State private var destinationPath: String
    @State private var strategy: USBCopyStrategy
    @State private var enableRotation: Bool
    @State private var rotationPolicy: USBCopyRotationPolicy
    @State private var maxVersionCount: Int
    @State private var removeSourceFile: Bool
    @State private var notKeepDirectoryStructure: Bool
    @State private var smartCreateDateDirectory: Bool
    @State private var renamePhotoVideo: Bool
    @State private var conflictPolicy: USBCopyConflictPolicy
    @State private var trigger: USBCopyTrigger
    @State private var filterSelection: USBCopyFilterSelection
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showMirrorConfirmation = false
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        localShares: [SharedFolder],
        externalShares: [SharedFolder],
        loadFolders: @escaping (String) async throws -> [FileStationItem],
        onCreate: @escaping (USBCopyTaskCreation) async -> DSMOperationOutcome
    ) {
        task = nil
        self.localShares = localShares
        self.externalShares = externalShares
        self.loadFolders = loadFolders
        self.onCreate = onCreate
        onSave = nil
        let initialType = USBCopyTaskType.exportGeneral
        let filter = USBCopyFilter.defaultValue(for: initialType)
        _type = State(initialValue: initialType)
        _name = State(initialValue: "")
        _sourcePath = State(initialValue: localShares.first.map { "/\($0.name)" } ?? "")
        _destinationPath = State(initialValue: externalShares.first.map { "/\($0.name)" } ?? "")
        _strategy = State(initialValue: .versioning)
        _enableRotation = State(initialValue: false)
        _rotationPolicy = State(initialValue: .oldestVersion)
        _maxVersionCount = State(initialValue: 256)
        _removeSourceFile = State(initialValue: false)
        _notKeepDirectoryStructure = State(initialValue: false)
        _smartCreateDateDirectory = State(initialValue: false)
        _renamePhotoVideo = State(initialValue: false)
        _conflictPolicy = State(initialValue: .rename)
        _trigger = State(initialValue: USBCopyTrigger(
            runWhenPlugIn: false,
            ejectWhenTaskDone: true,
            scheduleEnabled: false,
            scheduleContent: .defaultValue
        ))
        _filterSelection = State(initialValue: USBCopyFilterSelection(filter: filter))
    }

    init(
        details: USBCopyTaskDetails,
        localShares: [SharedFolder],
        externalShares: [SharedFolder],
        loadFolders: @escaping (String) async throws -> [FileStationItem],
        onSave: @escaping (USBCopyTaskSettings) async -> DSMOperationOutcome
    ) {
        let task = details.task
        self.task = task
        self.localShares = localShares
        self.externalShares = externalShares
        self.loadFolders = loadFolders
        onCreate = nil
        self.onSave = onSave
        _type = State(initialValue: task.knownType ?? .exportGeneral)
        _name = State(initialValue: task.name)
        _sourcePath = State(initialValue: task.sourcePath)
        _destinationPath = State(initialValue: task.destinationPath)
        let isPhotoImport = task.knownType == .importPhoto
        _strategy = State(initialValue: isPhotoImport ? .incremental : task.knownStrategy ?? .versioning)
        _enableRotation = State(initialValue: isPhotoImport ? false : task.enableRotation ?? false)
        _rotationPolicy = State(initialValue: task.rotationPolicy.flatMap(USBCopyRotationPolicy.init) ?? .oldestVersion)
        _maxVersionCount = State(initialValue: task.maxVersionCount ?? 256)
        _removeSourceFile = State(initialValue: task.removeSourceFile ?? false)
        _notKeepDirectoryStructure = State(
            initialValue: isPhotoImport || (task.notKeepDirectoryStructure ?? false)
        )
        let keepsNoStructure = task.notKeepDirectoryStructure ?? false
        let renamesPhotoVideo = task.renamePhotoVideo ?? false
        _smartCreateDateDirectory = State(
            initialValue: isPhotoImport
                || (task.smartCreateDateDirectory ?? (keepsNoStructure && !renamesPhotoVideo))
        )
        _renamePhotoVideo = State(initialValue: isPhotoImport || (task.renamePhotoVideo ?? false))
        _conflictPolicy = State(
            initialValue: isPhotoImport
                ? .rename
                : task.conflictPolicy.flatMap(USBCopyConflictPolicy.init) ?? .rename
        )
        _trigger = State(initialValue: details.trigger)
        _filterSelection = State(initialValue: USBCopyFilterSelection(filter: details.filter))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(task == nil ? "Créer une tâche USB Copy" : "Modifier la tâche USB Copy")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($contentFocused)
                .padding()

            Form {
                Section("Tâche") {
                    Picker("Direction", selection: $type) {
                        ForEach(USBCopyTaskType.allCases) { taskType in
                            Text(taskType.localizedName).tag(taskType)
                        }
                    }
                    .disabled(task != nil)
                    .help("Choisir le sens de la copie")

                    if task?.isDefaultTask == true {
                        LabeledContent("Nom de la tâche") {
                            Text(verbatim: name)
                                .textSelection(.enabled)
                        }
                    } else {
                        TextField("Nom de la tâche", text: $name)
                            .focused($nameFocused)
                            .help("Nom de la tâche USB Copy, jusqu’à 64 caractères")
                    }

                    USBCopyPathField(
                        label: "Dossier source",
                        pickerLabel: "Choisir le dossier source",
                        path: $sourcePath,
                        shares: sourceShares,
                        loadFolders: loadFolders,
                        isDisabled: task != nil
                    )
                    USBCopyPathField(
                        label: "Dossier de destination",
                        pickerLabel: "Choisir le dossier de destination",
                        path: $destinationPath,
                        shares: editableDestinationShares,
                        loadFolders: loadFolders,
                        isDisabled: destinationPathIsDisabled
                    )

                    if destinationPathIsDisabled {
                        Label(
                            "Le périphérique associé à cette tâche n’est pas connecté. Le dossier de destination ne peut pas être modifié.",
                            systemImage: "externaldrive.badge.xmark"
                        )
                        .foregroundStyle(.secondary)
                    }

                    if enablesDefaultTaskOnSave {
                        Label(
                            "Choisissez un dossier sur le périphérique USB. La tâche sera enregistrée puis activée.",
                            systemImage: "externaldrive.badge.plus"
                        )
                        .foregroundStyle(.secondary)
                    }

                    if externalShares.isEmpty {
                        Label(
                            task == nil
                                ? "Aucun dossier USB ou carte SD n’est actuellement monté. La création d’une tâche exige normalement un périphérique connecté."
                                : "Aucun dossier USB ou carte SD n’est actuellement monté. Connectez le périphérique pour choisir une autre destination.",
                            systemImage: "externaldrive.badge.questionmark"
                        )
                        .foregroundStyle(.secondary)
                    }

                    Picker("Mode de copie", selection: $strategy) {
                        ForEach(USBCopyStrategy.allCases) { copyStrategy in
                            Text(copyStrategy.localizedName).tag(copyStrategy)
                        }
                    }
                    .disabled(task != nil || type == .importPhoto)
                    .help("Choisir comment USB Copy met à jour la destination")
                }

                if strategy == .versioning {
                    Section("Rotation des versions") {
                        Toggle("Activer la rotation des versions", isOn: $enableRotation)
                        Picker("Règle de rotation", selection: $rotationPolicy) {
                            ForEach(USBCopyRotationPolicy.allCases) { policy in
                                Text(policy.localizedName).tag(policy)
                            }
                        }
                        .disabled(!enableRotation)
                        Stepper(value: $maxVersionCount, in: 1...65_535) {
                            Text("Nombre maximal de versions : \(maxVersionCount)")
                        }
                        .disabled(!enableRotation)
                    }
                }

                if strategy == .incremental {
                    Section("Copie incrémentielle") {
                        Toggle("Supprimer les fichiers source après la copie", isOn: $removeSourceFile)
                            .help("Déplacer les fichiers au lieu de les conserver à la source")
                        Toggle("Ne pas conserver la structure des dossiers", isOn: $notKeepDirectoryStructure)
                            .disabled(type == .importPhoto)
                        if notKeepDirectoryStructure {
                            if type == .importPhoto {
                                LabeledContent("Organisation") {
                                    Text(USBCopyFlatOrganization.dateDirectoriesAndRename.localizedName)
                                }
                            } else {
                                Picker("Organisation", selection: organizationBinding) {
                                    ForEach(USBCopyFlatOrganization.allCases) { organization in
                                        Text(organization.localizedName).tag(organization)
                                    }
                                }
                            }
                        }
                        if type == .importPhoto {
                            LabeledContent("En cas de conflit") {
                                Text(USBCopyConflictPolicy.rename.localizedName)
                            }
                        } else {
                            Picker("En cas de conflit", selection: $conflictPolicy) {
                                ForEach(USBCopyConflictPolicy.allCases) { policy in
                                    Text(policy.localizedName).tag(policy)
                                }
                            }
                        }
                    }
                }

                if task == nil {
                    Section("Déclenchement") {
                        USBCopyScheduleFields(
                            trigger: $trigger,
                            showsSchedule: type != .importPhoto
                        )
                    }
                    Section("Filtre de fichiers") {
                        USBCopyFilterFields(selection: $filterSelection)
                    }
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
                if isSaving {
                    ProgressView("Enregistrement…")
                        .controlSize(.small)
                }
                Spacer()
                Button("Annuler", role: .cancel, action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button(
                    task == nil
                        ? "Créer"
                        : enablesDefaultTaskOnSave ? "Enregistrer et activer" : "Enregistrer",
                    action: requestSave
                )
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
                    .confirmationDialog(
                        "Créer une copie miroir ?",
                        isPresented: $showMirrorConfirmation
                    ) {
                        Button("Créer la tâche miroir", role: .destructive) {
                            Task { await save() }
                        }
                        Button("Annuler", role: .cancel) { }
                    } message: {
                        Text("USB Copy supprimera de la destination les fichiers qui ne sont plus présents à la source. Vérifiez soigneusement le dossier de destination.")
                    }
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 680)
        .onAppear {
            if task == nil { nameFocused = true }
            contentFocused = true
            VoiceOver.announce(
                task == nil
                    ? String(localized: "Créer une tâche USB Copy")
                    : String(localized: "Modifier la tâche USB Copy"),
                category: .navigation
            )
        }
        .onChange(of: type) { oldValue, newValue in
            guard task == nil, oldValue != newValue else { return }
            strategy = newValue == .importPhoto ? .incremental : .versioning
            let defaultFilter = USBCopyFilter.defaultValue(for: newValue)
            filterSelection = USBCopyFilterSelection(filter: defaultFilter)
            notKeepDirectoryStructure = newValue == .importPhoto
            smartCreateDateDirectory = newValue == .importPhoto
            renamePhotoVideo = newValue == .importPhoto
            sourcePath = sourceShares.first.map { "/\($0.name)" } ?? ""
            destinationPath = destinationShares.first.map { "/\($0.name)" } ?? ""
        }
        .onChange(of: notKeepDirectoryStructure) { _, doesNotKeepStructure in
            if doesNotKeepStructure && !smartCreateDateDirectory && !renamePhotoVideo {
                smartCreateDateDirectory = true
            } else if !doesNotKeepStructure {
                smartCreateDateDirectory = false
                renamePhotoVideo = false
            }
        }
    }

    private var sourceShares: [SharedFolder] { type.isImport ? externalShares : localShares }
    private var destinationShares: [SharedFolder] { type.isImport ? localShares : externalShares }

    private var editableDestinationShares: [SharedFolder] {
        guard task != nil, type == .exportGeneral, !destinationPath.isEmpty,
              let rootName = destinationPath.split(separator: "/").first.map(String.init) else {
            return destinationShares
        }
        return destinationShares.filter { $0.name == rootName }
    }

    private var destinationPathIsDisabled: Bool {
        task != nil && type == .exportGeneral && !destinationPath.isEmpty && task?.isUSBMounted != true
    }

    private var enablesDefaultTaskOnSave: Bool {
        task?.isDefaultTask == true && task?.canEnable == true
            && task?.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
    }

    private var organizationBinding: Binding<USBCopyFlatOrganization> {
        Binding(
            get: {
                switch (smartCreateDateDirectory, renamePhotoVideo) {
                case (false, true): .renamePhotoVideo
                case (true, true): .dateDirectoriesAndRename
                default: .dateDirectories
                }
            },
            set: { organization in
                smartCreateDateDirectory = organization != .renamePhotoVideo
                renamePhotoVideo = organization != .dateDirectories
            }
        )
    }

    private func requestSave() {
        guard validate() else { return }
        if task == nil && strategy == .mirror {
            showMirrorConfirmation = true
        } else {
            Task { await save() }
        }
    }

    private func validate() -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSource = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDestination = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty || trimmedName.count > 64 {
            return failValidation(String(localized: "Saisissez un nom de tâche de 1 à 64 caractères."))
        }
        if trimmedSource.isEmpty || trimmedDestination.isEmpty {
            return failValidation(String(localized: "Choisissez un dossier source et un dossier de destination."))
        }
        if trigger.scheduleEnabled && !trigger.scheduleContent.hasSelectedWeekday {
            return failValidation(String(localized: "Choisissez au moins un jour d’exécution."))
        }
        if trigger.scheduleEnabled && !trigger.scheduleContent.hasValidReferenceDate {
            return failValidation(String(localized: "Saisissez une date de référence valide au format AAAA/MM/JJ."))
        }
        if strategy == .versioning && !(1...65_535).contains(maxVersionCount) {
            return failValidation(String(localized: "Le nombre maximal de versions doit être compris entre 1 et 65 535."))
        }
        return true
    }

    private func failValidation(_ message: String) -> Bool {
        errorMessage = message
        errorFocused = true
        VoiceOver.announce(message, category: .error, priority: .high)
        return false
    }

    private func save() async {
        guard validate() else { return }
        isSaving = true
        errorMessage = nil
        VoiceOver.announce(String(localized: "Enregistrement de la tâche USB Copy…"), category: .progress)
        let outcome: DSMOperationOutcome
        if let task, let onSave {
            outcome = await onSave(USBCopyTaskSettings(
                id: task.id,
                type: type,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sourcePath: sourcePath.trimmingCharacters(in: .whitespacesAndNewlines),
                destinationPath: destinationPath.trimmingCharacters(in: .whitespacesAndNewlines),
                copyStrategy: strategy,
                enableRotation: strategy == .versioning && enableRotation,
                rotationPolicy: rotationPolicy,
                maxVersionCount: maxVersionCount,
                removeSourceFile: strategy == .incremental && removeSourceFile,
                notKeepDirectoryStructure: type == .importPhoto
                    || (strategy == .incremental && notKeepDirectoryStructure),
                smartCreateDateDirectory: type == .importPhoto
                    || (strategy == .incremental && smartCreateDateDirectory),
                renamePhotoVideo: type == .importPhoto
                    || (strategy == .incremental && renamePhotoVideo),
                conflictPolicy: type == .importPhoto ? .rename : conflictPolicy
            ))
        } else if let onCreate {
            outcome = await onCreate(creation)
        } else {
            outcome = .failure(String(localized: "Impossible d’enregistrer cette tâche."))
        }
        isSaving = false
        handle(outcome)
    }

    private var creation: USBCopyTaskCreation {
        USBCopyTaskCreation(
            type: type,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourcePath: sourcePath.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationPath: destinationPath.trimmingCharacters(in: .whitespacesAndNewlines),
            copyStrategy: strategy,
            enableRotation: strategy == .versioning ? enableRotation : nil,
            rotationPolicy: strategy == .versioning ? rotationPolicy : nil,
            maxVersionCount: strategy == .versioning ? maxVersionCount : nil,
            removeSourceFile: strategy == .incremental ? removeSourceFile : false,
            notKeepDirectoryStructure: strategy == .incremental
                ? type == .importPhoto || notKeepDirectoryStructure
                : nil,
            smartCreateDateDirectory: strategy == .incremental
                ? type == .importPhoto || smartCreateDateDirectory
                : nil,
            renamePhotoVideo: strategy == .incremental
                ? type == .importPhoto || renamePhotoVideo
                : nil,
            conflictPolicy: strategy == .incremental
                ? (type == .importPhoto ? .rename : conflictPolicy)
                : nil,
            runWhenPlugIn: trigger.runWhenPlugIn,
            ejectWhenTaskDone: trigger.ejectWhenTaskDone,
            scheduleEnabled: type == .importPhoto ? false : trigger.scheduleEnabled,
            scheduleContent: trigger.scheduleContent,
            filter: filterSelection.filter
        )
    }

    private func handle(_ outcome: DSMOperationOutcome) {
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
}

private struct USBCopyPathField: View {
    let label: LocalizedStringKey
    let pickerLabel: LocalizedStringKey
    @Binding var path: String
    let shares: [SharedFolder]
    let loadFolders: (String) async throws -> [FileStationItem]
    let isDisabled: Bool

    @State private var showsFolderPicker = false

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(verbatim: path)
                    .textSelection(.enabled)
                Button(pickerLabel, systemImage: "folder") {
                    showsFolderPicker = true
                }
                .labelStyle(.iconOnly)
                .disabled(isDisabled || shares.isEmpty)
                .help("Choisir un dossier partagé dans la liste")
            }
        }
        .sheet(isPresented: $showsFolderPicker) {
            USBCopyFolderPickerSheet(
                initialPath: path,
                shares: shares,
                loadFolders: loadFolders
            ) { selectedPath in
                path = selectedPath
            }
        }
    }
}

private enum USBCopyFlatOrganization: CaseIterable, Identifiable {
    case dateDirectories
    case renamePhotoVideo
    case dateDirectoriesAndRename

    var id: Self { self }

    var localizedName: LocalizedStringKey {
        switch self {
        case .dateDirectories: "Créer des dossiers selon la date"
        case .renamePhotoVideo: "Renommer les photos et vidéos selon la date"
        case .dateDirectoriesAndRename: "Créer des dossiers et renommer les photos et vidéos selon la date"
        }
    }
}
