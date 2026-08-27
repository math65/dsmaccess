//
//  SharesView.swift
//  dsmaccess
//  Administration of DSM shared folders.

import AppKit
import SwiftUI

struct SharesView: View {
    @State private var vm: SharesViewModel
    @State private var showCreateSheet = false
    @State private var pendingEdit: SharedFolder?
    @State private var pendingUnlock: SharedFolder?
    @State private var pendingDelete: SharedFolder?
    @State private var pendingPermissions: SharedFolder?
    @State private var pendingRecycleBin: SharedFolder?
    @State private var searchText = ""
    @State private var selection = Set<SharedFolder.ID>()
    @State private var order = [KeyPathComparator(\SharedFolder.sortableName, order: .forward)]
    @AccessibilityFocusState private var focusContent: Bool

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
        _vm = State(initialValue: SharesViewModel(session: session))
    }

    var body: some View {
        content
        .searchable(text: $searchText, prompt: "shares.search.label")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("shares.refresh.button")
            }

            ToolbarItem {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("shares.create.button", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("shares.create.button")
            }
        }
        .task {
            await load(restoresInitialFocus: true)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateShareSheet(volumes: vm.volumes) { creation in
                Task {
                    let outcome = await vm.create(creation)
                    OperationFailures.shared.present(outcome, from: .shares)
                }
            }
        }
        .sheet(item: $pendingEdit) { folder in
            EditShareSheet(folder: folder) { changes in
                Task {
                    let outcome = await vm.update(changes)
                    OperationFailures.shared.present(outcome, from: .shares)
                }
            }
        }
        .sheet(item: $pendingUnlock) { folder in
            UnlockShareSheet(folder: folder) { key in
                Task {
                    let outcome = await vm.unlock(folder, key: key)
                    OperationFailures.shared.present(outcome, from: .shares)
                }
            }
        }
        .sheet(item: $pendingDelete) { folder in
            DeleteShareSheet(folder: folder) {
                Task {
                    let msg = await vm.delete(folder)
                    OperationFailures.shared.present(msg, from: .shares)
                }
            }
        }
        .sheet(item: $pendingPermissions) { folder in
            ShareAccountPermissionsSheet(shareName: folder.name, session: session) { outcome in
                OperationFailures.shared.present(outcome, from: .shares)
            }
        }
        .confirmationDialog(
            Text(String(localized: "shares.recycle_bin.empty.confirm.title", defaultValue: "Empty the recycle bin of “\(pendingRecycleBin?.displayName ?? "")”?")),
            isPresented: Binding(
                get: { pendingRecycleBin != nil },
                set: { if !$0 { pendingRecycleBin = nil } }
            ),
            presenting: pendingRecycleBin
        ) { folder in
            Button("shares.recycle_bin.empty.button", role: .destructive) {
                Task {
                    let outcome = await vm.emptyRecycleBin(folder)
                    OperationFailures.shared.present(outcome, from: .shares)
                }
            }
            Button("common.button.cancel", role: .cancel) { }
        } message: { _ in
            Text("shares.recycle_bin.empty.confirm.message")
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let conversion = vm.conversion {
                conversionBanner(conversion)
                Divider()
            }
            table
        }
    }

    /// A conversion leaves its folder unreachable for as long as it runs, so it is stated on
    /// screen rather than only announced once.
    @ViewBuilder
    private func conversionBanner(_ conversion: SharesViewModel.ShareConversion) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: Double(conversion.percent), total: 100)
                .frame(width: 120)
                .accessibilityHidden(true)
            Text(String(localized: "shares.conversion.banner", defaultValue: "\(conversion.folderName) is being rewritten by the NAS: \(conversion.percent)%. It stays unavailable until this finishes."))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("shares.conversion.stop.button") {
                Task {
                    if let outcome = await vm.cancelConversion() {
                        OperationFailures.shared.present(outcome, from: .shares)
                    }
                }
            }
            .help("shares.conversion.stop.hint")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var table: some View {
        if vm.isLoading && vm.shares.isEmpty {
            ModuleLoadingView()
                .accessibilityFocused($focusContent)
        } else if let error = vm.errorMessage {
            ModuleErrorView(message: error) {
                Task { await load() }
            }
            .accessibilityFocused($focusContent)
        } else if vm.shares.isEmpty {
            EmptyModuleView(
                title: "common.empty.shared_folders",
                systemImage: "externaldrive.badge.person.crop",
                description: "shares.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else if filteredShares.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            Table(
                filteredShares.sorted(using: order),
                selection: $selection,
                sortOrder: $order
            ) {
                TableColumn("common.column.name", value: \.sortableName) { share in
                    Text(share.displayName)
                }
                TableColumn("common.column.volume", value: \.sortableVolume) { share in
                    TableValueText(share.volumeText)
                }
                TableColumn("common.column.description", value: \.sortableDescription) { share in
                    TableValueText(share.desc)
                }
                TableColumn("common.column.recycle_bin", value: \.sortableRecycleBin) { share in
                    Text(share.recycleBinDescription)
                }
                TableColumn("shares.column.encryption", value: \.sortableEncryption) { share in
                    Text(share.encryptionDescription)
                }
            }
            .accessibilityLabel("common.module.shared_folders")
            .accessibilityFocused($focusContent)
            .contextMenu(forSelectionType: SharedFolder.ID.self) { ids in
                shareActions(for: vm.shares.first { ids.contains($0.id) })
            }
        }
    }

    /// Every action stays listed and merely disabled when it does not apply, so the menu keeps
    /// the same shape from one row to the next.
    @ViewBuilder
    private func shareActions(for share: SharedFolder?) -> some View {
        Button("shares.edit.button") { pendingEdit = share }
            .disabled(share == nil || share?.encryptionState == .locked)

        if share?.encryptionState == .locked {
            Button("shares.unlock.menu") { pendingUnlock = share }
        } else {
            Button("shares.lock.button") {
                guard let share else { return }
                Task {
                    let outcome = await vm.lock(share)
                    OperationFailures.shared.present(outcome, from: .shares)
                }
            }
            .disabled(share?.encryptionState != .mounted)
        }

        Divider()

        Button("shares.permissions.button") { pendingPermissions = share }
            .disabled(share == nil)

        Button("shares.recycle_bin.empty.menu") { pendingRecycleBin = share }
            .disabled(share?.recycleBinEnabled != true)

        Divider()

        Button("shares.smb_path.copy.button") {
            guard let share else { return }
            copySMBPath(for: share)
        }
        .disabled(share == nil || session.connectionTarget?.directEndpoint == nil)

        Divider()

        Button("common.menu.delete", role: .destructive) { pendingDelete = share }
            .disabled(share == nil)
    }

    private var filteredShares: [SharedFolder] {
        guard !searchText.isEmpty else { return vm.shares }
        return vm.shares.filter {
            $0.displayName.localizedStandardContains(searchText)
                || ($0.desc?.localizedStandardContains(searchText) == true)
                || ($0.volumeText?.localizedStandardContains(searchText) == true)
        }
    }

    private func copySMBPath(for share: SharedFolder) {
        guard let host = session.connectionTarget?.directEndpoint?.host else { return }
        let path = "smb://\(host)/\(share.displayName)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        VoiceOver.announce(String(localized: "shares.smb_path.copied"))
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "shares.loading"),
            category: .progress,
            priority: .low
        )
        await vm.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        }
        VoiceOver.announce(
            vm.summary,
            category: vm.errorMessage == nil ? .result : .error
        )
    }
}

// MARK: - Shared settings

/// The settings both sheets offer, so creating and editing a folder read the same way.
private struct ShareSettingsSections: View {
    @Binding var description: String
    @Binding var recycleBinEnabled: Bool
    @Binding var recycleBinAdminOnly: Bool
    @Binding var hidden: Bool
    @Binding var hidesUnreadableItems: Bool

    var body: some View {
        Section("shares.section.identity") {
            TextField("common.field.description_optional", text: $description)
                .help("shares.create.description.label")
        }

        Section("shares.section.recycle_bin") {
            Toggle("shares.option.recycle_bin.label", isOn: $recycleBinEnabled)
                .accessibilityHint("shares.option.recycle_bin.hint")
            Toggle("shares.option.recycle_bin.admin_only.label", isOn: $recycleBinAdminOnly)
                .accessibilityHint("shares.option.recycle_bin.admin_only.hint")
                .disabled(!recycleBinEnabled)
        }

        Section("shares.section.visibility") {
            Toggle("shares.option.hidden.label", isOn: $hidden)
                .accessibilityHint("shares.option.hidden.hint")
            Toggle("shares.option.hide_unreadable.label", isOn: $hidesUnreadableItems)
                .accessibilityHint("shares.option.hide_unreadable.hint")
        }
    }
}

/// Storage settings. DSM stores the quota in megabytes; it is offered in gigabytes here, as on
/// DSM's own screen, where a quota is never expressed in megabytes either.
private struct ShareStorageSection: View {
    @Binding var compressionEnabled: Bool
    @Binding var limitsSize: Bool
    @Binding var quotaGigabytes: Int
    /// Only shown when creating: DSM never lets the checksum be changed afterwards.
    var checksumEnabled: Binding<Bool>?

    static let megabytesPerGigabyte = 1024

    var body: some View {
        Section("shares.section.storage") {
            if let checksumEnabled {
                Toggle("shares.option.checksum.label", isOn: checksumEnabled)
                    .accessibilityHint("shares.option.checksum.hint")
            }
            Toggle("shares.option.compression.label", isOn: $compressionEnabled)
                .accessibilityHint("shares.option.compression.hint")
            Toggle("shares.option.quota.label", isOn: $limitsSize)
                .accessibilityHint("shares.option.quota.hint")
            if limitsSize {
                TextField(
                    "shares.option.quota.value.label",
                    value: $quotaGigabytes,
                    format: .number
                )
                .help("shares.option.quota.value.hint")
            }
        }
    }
}

/// The restrictions DSM groups under "Advanced permissions". They apply on top of the access
/// rights, and only to File Station, FTP and WebDAV.
private struct ShareRestrictionsSection: View {
    @Binding var disablesListing: Bool
    @Binding var disablesModification: Bool
    @Binding var disablesDownload: Bool

    var body: some View {
        Section("shares.section.restrictions") {
            Toggle("shares.option.disable_list.label", isOn: $disablesListing)
                .accessibilityHint("shares.option.disable_list.hint")
            Toggle("shares.option.disable_modify.label", isOn: $disablesModification)
                .accessibilityHint("shares.option.disable_modify.hint")
            Toggle("shares.option.disable_download.label", isOn: $disablesDownload)
                .accessibilityHint("shares.option.disable_download.hint")
        }
    }
}

/// The two key fields and the warning that goes with them. The rules they are checked against
/// live in `ShareEncryptionKey`.
private struct EncryptionKeyFields: View {
    @Binding var key: String
    @Binding var confirmation: String

    var body: some View {
        LabeledField(label: "shares.encryption.key.label") {
            SecureField("", text: $key)
                .help("shares.encryption.key.hint")
        }
        LabeledField(label: "shares.encryption.key.confirm.label") {
            SecureField("", text: $confirmation)
                .help("shares.encryption.key.confirm.hint")
        }
        Text("shares.encryption.key.warning")
            .font(.callout)
            .foregroundStyle(.readableOrange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Creation

private struct CreateShareSheet: View {
    let volumes: [String]
    let onConfirm: (SharedFolderCreation) -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var volume: String
    @State private var recycleBinEnabled = true
    @State private var recycleBinAdminOnly = true
    @State private var hidden = false
    @State private var hidesUnreadableItems = false
    @State private var checksumEnabled = false
    @State private var compressionEnabled = false
    @State private var limitsSize = false
    @State private var quotaGigabytes = 10
    @State private var encrypts = false
    @State private var key = ""
    @State private var keyConfirmation = ""
    @FocusState private var nameFocused: Bool
    @AccessibilityFocusState private var a11yFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(volumes: [String], onConfirm: @escaping (SharedFolderCreation) -> Void) {
        self.volumes = volumes
        self.onConfirm = onConfirm
        _volume = State(initialValue: volumes.first ?? "/volume1")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var keyProblem: String? {
        guard encrypts else { return nil }
        return ShareEncryptionKey.problem(key: key, confirmation: keyConfirmation)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("shares.create.button")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)

            Divider()

            Form {
                Section {
                    TextField("shares.name.column", text: $name)
                        .focused($nameFocused)
                        .accessibilityFocused($a11yFocused)
                        .help("shares.create.name.label")

                    if volumes.count > 1 {
                        Picker("common.column.volume", selection: $volume) {
                            ForEach(volumes, id: \.self) { v in
                                Text(volumeLabel(for: v)).tag(v)
                            }
                        }
                        .help("shares.create.volume.label")
                    }
                }

                ShareSettingsSections(
                    description: $description,
                    recycleBinEnabled: $recycleBinEnabled,
                    recycleBinAdminOnly: $recycleBinAdminOnly,
                    hidden: $hidden,
                    hidesUnreadableItems: $hidesUnreadableItems
                )

                ShareStorageSection(
                    compressionEnabled: $compressionEnabled,
                    limitsSize: $limitsSize,
                    quotaGigabytes: $quotaGigabytes,
                    checksumEnabled: $checksumEnabled
                )

                Section("shares.section.encryption") {
                    Toggle("shares.encryption.enable.label", isOn: $encrypts)
                        .accessibilityHint("shares.encryption.enable.hint")
                    if encrypts {
                        EncryptionKeyFields(key: $key, confirmation: $keyConfirmation)
                        if let keyProblem {
                            Text(keyProblem)
                                .foregroundStyle(.readableRed)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("shares.create.fields.label")

            Divider()

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("shares.create.cancel.button")
                Button("common.button.create", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || keyProblem != nil)
                    .help("shares.create.confirm.button")
            }
            .padding()
        }
        .frame(width: 480, height: 560)
        .onAppear {
            nameFocused = true
            a11yFocused = true
            VoiceOver.announce(
                String(localized: "shares.create.button"),
                category: .navigation
            )
        }
    }

    private func confirm() {
        let value = trimmedName
        guard !value.isEmpty, keyProblem == nil else { return }
        onConfirm(
            SharedFolderCreation(
                name: value,
                volumePath: volume,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                recycleBinEnabled: recycleBinEnabled,
                recycleBinAdminOnly: recycleBinAdminOnly,
                hidden: hidden,
                hidesUnreadableItems: hidesUnreadableItems,
                checksumEnabled: checksumEnabled,
                compressionEnabled: compressionEnabled,
                quotaMegabytes: limitsSize
                    ? quotaGigabytes * ShareStorageSection.megabytesPerGigabyte
                    : nil,
                encryptionKey: encrypts ? key : nil
            )
        )
        dismiss()
    }
}

// MARK: - Editing

private struct EditShareSheet: View {
    let folder: SharedFolder
    let onConfirm: (SharedFolderChanges) -> Void

    @State private var description: String
    @State private var recycleBinEnabled: Bool
    @State private var recycleBinAdminOnly: Bool
    @State private var hidden: Bool
    @State private var hidesUnreadableItems: Bool
    @State private var compressionEnabled: Bool
    @State private var limitsSize: Bool
    @State private var quotaGigabytes: Int
    @State private var disablesListing: Bool
    @State private var disablesModification: Bool
    @State private var disablesDownload: Bool
    @State private var encrypts: Bool
    @State private var key = ""
    @State private var keyConfirmation = ""
    @AccessibilityFocusState private var focusHeading: Bool
    @Environment(\.dismiss) private var dismiss

    init(folder: SharedFolder, onConfirm: @escaping (SharedFolderChanges) -> Void) {
        self.folder = folder
        self.onConfirm = onConfirm
        _description = State(initialValue: folder.desc ?? "")
        _recycleBinEnabled = State(initialValue: folder.recycleBinEnabled == true)
        _recycleBinAdminOnly = State(initialValue: folder.recycleBinAdminOnly == true)
        _hidden = State(initialValue: folder.hidden == true)
        _hidesUnreadableItems = State(initialValue: folder.hidesUnreadableItems == true)
        _compressionEnabled = State(initialValue: folder.compressionEnabled == true)
        let quota = folder.quotaMegabytes ?? 0
        _limitsSize = State(initialValue: quota > 0)
        _quotaGigabytes = State(
            initialValue: quota > 0 ? quota / ShareStorageSection.megabytesPerGigabyte : 10
        )
        _disablesListing = State(initialValue: folder.disablesListing == true)
        _disablesModification = State(initialValue: folder.disablesModification == true)
        _disablesDownload = State(initialValue: folder.disablesDownload == true)
        _encrypts = State(initialValue: folder.encryptionState.isEncrypted)
    }

    private var wasEncrypted: Bool { folder.encryptionState.isEncrypted }

    /// Only a change of encryption needs a key: the folder is either being converted to
    /// encrypted, or having its encryption removed, and DSM asks for the key both ways.
    private var encryptionChange: ShareEncryptionChange? {
        switch (wasEncrypted, encrypts) {
        case (false, true): .encrypt(key: key)
        case (true, false): .decrypt(key: key)
        default: nil
        }
    }

    private var keyProblem: String? {
        switch encryptionChange {
        case .encrypt:
            ShareEncryptionKey.problem(key: key, confirmation: keyConfirmation)
        case .decrypt:
            key.isEmpty ? String(localized: "shares.encryption.key.required") : nil
        case nil:
            nil
        }
    }

    private var changes: SharedFolderChanges {
        guard let volumePath = folder.volPath else {
            // DSM answers 403 without vol_path; the guard keeps that failure impossible rather
            // than sending a request that cannot work.
            return SharedFolderChanges(name: folder.name, volumePath: "")
        }
        var changes = SharedFolderChanges(name: folder.name, volumePath: volumePath)
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (folder.desc ?? "") { changes.description = trimmed }
        if recycleBinEnabled != (folder.recycleBinEnabled == true) {
            changes.recycleBinEnabled = recycleBinEnabled
        }
        if recycleBinAdminOnly != (folder.recycleBinAdminOnly == true) {
            changes.recycleBinAdminOnly = recycleBinAdminOnly
        }
        if hidden != (folder.hidden == true) { changes.hidden = hidden }
        if hidesUnreadableItems != (folder.hidesUnreadableItems == true) {
            changes.hidesUnreadableItems = hidesUnreadableItems
        }
        if compressionEnabled != (folder.compressionEnabled == true) {
            changes.compressionEnabled = compressionEnabled
        }
        if quotaMegabytes != (folder.quotaMegabytes ?? 0) {
            changes.quotaMegabytes = quotaMegabytes
        }
        if restrictions != loadedRestrictions {
            changes.advancedPermissions = restrictions
        }
        changes.encryption = encryptionChange
        return changes
    }

    private var quotaMegabytes: Int {
        limitsSize ? quotaGigabytes * ShareStorageSection.megabytesPerGigabyte : 0
    }

    private var restrictions: SharedFolderChanges.AdvancedPermissions {
        .init(
            disablesListing: disablesListing,
            disablesModification: disablesModification,
            disablesDownload: disablesDownload
        )
    }

    private var loadedRestrictions: SharedFolderChanges.AdvancedPermissions {
        .init(
            disablesListing: folder.disablesListing == true,
            disablesModification: folder.disablesModification == true,
            disablesDownload: folder.disablesDownload == true
        )
    }

    private var canSave: Bool {
        folder.volPath != nil && keyProblem == nil && !changes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "shares.edit.title", defaultValue: "Settings for \(folder.displayName)"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)

            Divider()

            Form {
                ShareSettingsSections(
                    description: $description,
                    recycleBinEnabled: $recycleBinEnabled,
                    recycleBinAdminOnly: $recycleBinAdminOnly,
                    hidden: $hidden,
                    hidesUnreadableItems: $hidesUnreadableItems
                )

                ShareStorageSection(
                    compressionEnabled: $compressionEnabled,
                    limitsSize: $limitsSize,
                    quotaGigabytes: $quotaGigabytes
                )

                ShareRestrictionsSection(
                    disablesListing: $disablesListing,
                    disablesModification: $disablesModification,
                    disablesDownload: $disablesDownload
                )

                Section("shares.section.encryption") {
                    Toggle("shares.encryption.enable.label", isOn: $encrypts)
                        .accessibilityHint("shares.encryption.enable.hint")

                    switch encryptionChange {
                    case .encrypt:
                        EncryptionKeyFields(key: $key, confirmation: $keyConfirmation)
                        Text("shares.encryption.change.warning")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    case .decrypt:
                        LabeledField(label: "shares.encryption.key.current.label") {
                            SecureField("", text: $key)
                                .help("shares.encryption.key.current.hint")
                        }
                        Text("shares.encryption.change.warning")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    case nil:
                        EmptyView()
                    }

                    if let keyProblem {
                        Text(keyProblem)
                            .foregroundStyle(.readableRed)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("shares.edit.fields.label")

            Divider()

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("common.button.save") {
                    onConfirm(changes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 480, height: 540)
        .onAppear {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "shares.edit.title", defaultValue: "Settings for \(folder.displayName)"),
                category: .navigation
            )
        }
    }
}

// MARK: - Unlocking

private struct UnlockShareSheet: View {
    let folder: SharedFolder
    let onConfirm: (String) -> Void

    @State private var key = ""
    @FocusState private var keyFocused: Bool
    @AccessibilityFocusState private var a11yFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("shares.unlock.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(String(localized: "shares.unlock.message", defaultValue: "“\(folder.displayName)” is locked. Its key is needed to make its contents available again."))
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "shares.encryption.key.label") {
                SecureField("", text: $key)
                    .focused($keyFocused)
                    .accessibilityFocused($a11yFocused)
                    .help("shares.unlock.key.hint")
            }

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("shares.unlock.button") {
                    onConfirm(key)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            keyFocused = true
            a11yFocused = true
            VoiceOver.announce(
                String(localized: "shares.unlock.title"),
                category: .navigation
            )
        }
    }
}

// MARK: - Deletion

private struct DeleteShareSheet: View {
    let folder: SharedFolder
    let onConfirm: () -> Void

    @State private var typedName = ""
    @FocusState private var fieldFocused: Bool
    @AccessibilityFocusState private var a11yFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var nameMatches: Bool {
        typedName.trimmingCharacters(in: .whitespacesAndNewlines) == folder.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("shares.delete.confirm.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text(String(localized: "shares.delete.confirm.message", defaultValue: "“\(folder.displayName)” and all its contents will be permanently deleted. This action cannot be undone."))
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(label: "shares.delete.confirm.name_field.placeholder") {
                TextField(folder.displayName, text: $typedName)
                    .focused($fieldFocused)
                    .accessibilityFocused($a11yFocused)
                    .help("shares.delete.confirm.name_field.label")
            }

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("shares.delete.cancel.button")
                Button("shares.delete.confirm.button", role: .destructive) {
                    onConfirm()
                    dismiss()
                }
                .disabled(!nameMatches)
                .help("shares.delete.confirm.button.label")
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            fieldFocused = true
            a11yFocused = true
            VoiceOver.announce(
                String(localized: "shares.delete.confirm.instruction"),
                category: .navigation
            )
        }
    }
}
