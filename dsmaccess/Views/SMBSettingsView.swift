//
//  SMBSettingsView.swift
//  dsmaccess
//
//  The SMB tab of the file services: every setting DSM offers for the protocol Finder and
//  Windows Explorer use.
//
//  Split the way DSM splits it, which is also the way its API is split. The screen carries
//  the five settings of the main `set`; the twenty-seven others live behind an "Advanced
//  settings" sheet, matching the second `set`. Flattening both into one form put the
//  workgroup field and a Samba tunable at the same level, and made reaching the first
//  setting a walk past all of them.
//
//  Settings are edited then applied together. The NAS restarts Samba on each write, so a
//  screen that applied field by field would cut the shares once per switch.
//

import SwiftUI

struct SMBSettingsPane: View {
    /// Owned by the screen around it, so its toolbar can reload the visible tab.
    @Bindable var vm: SMBSettingsViewModel
    @State private var advancedEdit: SMBAdvancedEdit?
    @AccessibilityFocusState private var focusContent: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        content
            .task { await load(restoresInitialFocus: true) }
            // The sheet carries the settings it edits, so it shows what was on screen when
            // the button was pressed rather than whatever the draft holds when it draws.
            .sheet(item: $advancedEdit) { edit in
                SMBAdvancedSettingsSheet(initial: edit.settings) { edited in
                    vm.draft?.advanced = edited
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.applied == nil {
            ModuleLoadingView("smb.loading")
                .accessibilityFocused($focusContent)
        } else if let settings = Binding($vm.draft) {
            VStack(spacing: 0) {
                SMBSettingsForm(
                    settings: settings,
                    logsTransfers: $vm.draftLogsTransfers,
                    hasAdvancedChanges: vm.hasAdvancedChanges,
                    openAdvanced: { advancedEdit = SMBAdvancedEdit(settings: settings.wrappedValue.advanced) }
                )
                .accessibilityFocused($focusContent)
                // Editing while the NAS is applying would be overwritten by the read-back
                // that follows, without the user seeing their change disappear.
                .disabled(vm.isApplying)
                Divider()
                actionBar
            }
        } else {
            ModuleErrorView(
                message: vm.loadError ?? String(localized: "smb.load.error"),
                retry: { Task { await load() } }
            )
            .accessibilityFocused($focusError)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if vm.isApplying {
                ProgressView("smb.applying")
                    .controlSize(.small)
            } else if vm.hasChanges {
                Text("smb.changes.pending")
                    .foregroundStyle(.readableOrange)
            }
            Spacer()
            Button("smb.button.revert") { vm.revert() }
                .disabled(!vm.hasChanges || vm.isApplying)
                .help("smb.button.revert.help")
            Button("common.button.apply", action: apply)
                .keyboardShortcut(.defaultAction)
                .disabled(!vm.hasChanges || vm.isApplying || !isWorkgroupValid)
                // Why the button is unavailable is said here too: the message itself sits
                // beside the workgroup field, at the other end of the screen.
                .accessibilityHint(applyHint)
                .help("smb.button.apply.help")
        }
        .padding()
    }

    private var isWorkgroupValid: Bool {
        guard let draft = vm.draft else { return true }
        return !draft.basic.workgroup.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The type annotation is what makes both branches localization keys rather than plain
    /// strings, which would ship untranslated.
    private var applyHint: LocalizedStringKey {
        isWorkgroupValid ? "smb.button.apply.hint" : "smb.workgroup.required.hint"
    }

    // MARK: - Actions

    private func apply() {
        Task {
            VoiceOver.announce(
                String(localized: "smb.applying"),
                category: .progress,
                priority: .low
            )
            let outcome = await vm.apply()
            OperationFailures.shared.present(outcome, from: .fileServices)
        }
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "smb.loading"),
            category: .progress,
            priority: .low
        )
        await vm.load()
        guard !Task.isCancelled else { return }
        if restoresInitialFocus {
            await VoiceOver.restoreFocusIfCapturedByToolbar { focusContent = true }
        }
        if vm.loadError != nil {
            focusError = true
        }
        VoiceOver.announce(
            vm.summary,
            category: vm.loadError == nil ? .result : .error
        )
    }
}

/// What the advanced sheet edits, carried into it by `.sheet(item:)`.
private struct SMBAdvancedEdit: Identifiable {
    let id = UUID()
    var settings: SMBAdvancedSettings
}

// MARK: - Main form

/// The five settings DSM keeps on the screen itself, plus the way into the other twenty-seven.
private struct SMBSettingsForm: View {
    @Binding var settings: SMBSettings
    @Binding var logsTransfers: Bool
    let hasAdvancedChanges: Bool
    let openAdvanced: () -> Void

    /// DSM greys out every setting while the service is off. The section footer says so in
    /// words: a disabled control alone tells VoiceOver nothing about why.
    private var isServiceOff: Bool { !settings.basic.isEnabled }

    private var isWorkgroupValid: Bool {
        !settings.basic.workgroup.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("smb.section.service") {
                Toggle("smb.field.enable", isOn: $settings.basic.isEnabled)
                    .accessibilityHint("smb.field.enable.hint")
                TextField("smb.field.workgroup", text: $settings.basic.workgroup)
                    .disabled(isServiceOff)
                // The message sits right after the field it concerns: read in order, it
                // reaches the user where the problem is, not only at the foot of the screen
                // where the Apply button greys out.
                if !isWorkgroupValid {
                    Text("smb.workgroup.required")
                        .font(.callout)
                        .foregroundStyle(.readableRed)
                }
                if isServiceOff {
                    Text("smb.service.off.description")
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)
                }
            }

            Section("smb.section.sharing") {
                Toggle("smb.field.deny_previous_versions", isOn: $settings.basic.deniesPreviousVersions)
                    .accessibilityHint("smb.field.deny_previous_versions.hint")
                Toggle("smb.field.hide_unauthorized", isOn: $settings.basic.hidesUnauthorizedShares)
                    .accessibilityHint("smb.field.hide_unauthorized.hint")
                Toggle("smb.field.transfer_log", isOn: $logsTransfers)
                    .accessibilityHint("smb.field.transfer_log.hint")
            }
            .disabled(isServiceOff)

            Section {
                Button("smb.advanced.button", action: openAdvanced)
                    .accessibilityHint("smb.advanced.button.hint")
                    .help("smb.advanced.button.help")
                // Changes made in the sheet are invisible from here otherwise: the screen
                // shows none of the settings they touched.
                if hasAdvancedChanges {
                    Text("smb.advanced.changed")
                        .font(.callout)
                        .foregroundStyle(.readableOrange)
                }
            } footer: {
                Text("smb.advanced.description")
                    .foregroundStyle(.readableSecondary)
            }
            .disabled(isServiceOff)
        }
        .formStyle(.grouped)
        .accessibilityLabel("smb.form.label")
    }
}

// MARK: - Advanced sheet

/// The twenty-seven settings DSM puts behind its own "Advanced settings" button. Editing
/// happens on a copy: closing with Cancel leaves the screen as it was, and Save only moves
/// them back into the pending draft — the NAS is written by the screen's Apply button.
private struct SMBAdvancedSettingsSheet: View {
    @State private var settings: SMBAdvancedSettings
    let onSave: (SMBAdvancedSettings) -> Void

    @AccessibilityFocusState private var focusTitle: Bool
    @Environment(\.dismiss) private var dismiss

    init(initial: SMBAdvancedSettings, onSave: @escaping (SMBAdvancedSettings) -> Void) {
        _settings = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("smb.advanced.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            form

            Divider()

            HStack {
                Spacer()
                Button("common.button.cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("smb.advanced.cancel.help")
                Button("common.button.save") {
                    onSave(settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("smb.advanced.save.hint")
                .help("smb.advanced.save.help")
            }
            .padding(20)
        }
        .frame(width: 620, height: 620)
        .task { focusTitle = true }
    }

    private var form: some View {
        Form {
            Section("smb.section.protocol") {
                Picker("smb.field.min_protocol", selection: $settings.minimumProtocol) {
                    ForEach(SMBProtocolVersion.minimumChoices) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                .accessibilityHint("smb.field.min_protocol.hint")
                Picker("smb.field.max_protocol", selection: $settings.maximumProtocol) {
                    ForEach(SMBProtocolVersion.maximumChoices) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                .accessibilityHint("smb.field.max_protocol.hint")
                Picker("smb.field.encryption", selection: $settings.transportEncryption) {
                    ForEach(SMBTransportEncryption.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityHint("smb.field.encryption.hint")
                Picker("smb.field.signing", selection: $settings.serverSigning) {
                    ForEach(SMBServerSigning.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityHint("smb.field.signing.hint")
                TextField("smb.field.wins", text: $settings.winsServer)
                    .accessibilityHint("smb.field.wins.hint")
            }

            Section("smb.section.locking") {
                Toggle("smb.field.op_lock", isOn: $settings.opportunisticLocking)
                    .accessibilityHint("smb.field.op_lock.hint")
                Toggle("smb.field.smb2_leases", isOn: $settings.smb2FileLeases)
                    .accessibilityHint("smb.field.smb2_leases.hint")
                    .disabled(!settings.opportunisticLocking)
                Toggle("smb.field.smb3_directory_leasing", isOn: $settings.smb3DirectoryLeasing)
                    .accessibilityHint("smb.field.smb3_directory_leasing.hint")
                    .disabled(!settings.opportunisticLocking || !settings.smb2FileLeases)
                Toggle("smb.field.durable_handles", isOn: $settings.durableHandles)
                    .accessibilityHint("smb.field.durable_handles.hint")
                if !settings.opportunisticLocking {
                    Text("smb.locking.requires_op_lock")
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)
                }
            }

            Section("smb.section.macos") {
                Toggle("smb.field.mac_characters", isOn: $settings.macCharacterConversion)
                    .accessibilityHint("smb.field.mac_characters.hint")
                Toggle("smb.field.afp_cross_locking", isOn: $settings.crossProtocolLockingWithAFP)
                    .accessibilityHint("smb.field.afp_cross_locking.hint")
            }

            Section("smb.section.discovery") {
                Toggle("smb.field.local_master_browser", isOn: $settings.localMasterBrowser)
                    .accessibilityHint("smb.field.local_master_browser.hint")
                Toggle("smb.field.subfolder_notification", isOn: $settings.subfolderChangeNotification)
                    .accessibilityHint("smb.field.subfolder_notification.hint")
                Toggle("smb.field.dirsort", isOn: $settings.directorySorting)
                    .accessibilityHint("smb.field.dirsort.hint")
                Toggle("smb.field.wildcard_cache", isOn: $settings.wildcardSearchCache)
                    .accessibilityHint("smb.field.wildcard_cache.hint")
            }

            Section("smb.section.links") {
                Toggle("smb.field.symlinks", isOn: $settings.symbolicLinks)
                    .accessibilityHint("smb.field.symlinks.hint")
                Toggle("smb.field.wide_links", isOn: $settings.wideLinks)
                    .accessibilityHint("smb.field.wide_links.hint")
                    .disabled(!settings.symbolicLinks)
                Toggle("smb.field.unix_permissions", isOn: $settings.defaultUnixPermissions)
                    .accessibilityHint("smb.field.unix_permissions.hint")
            }

            Section("smb.section.performance") {
                Toggle("smb.field.async_read", isOn: $settings.asynchronousRead)
                    .accessibilityHint("smb.field.async_read.hint")
                Toggle("smb.field.multichannel", isOn: $settings.smb3Multichannel)
                    .accessibilityHint("smb.field.multichannel.hint")
                Toggle("smb.field.skip_allocation", isOn: $settings.skipsDiskAllocation)
                    .accessibilityHint("smb.field.skip_allocation.hint")
                Toggle("smb.field.immediate_sync", isOn: $settings.immediateSync)
                    .accessibilityHint("smb.field.immediate_sync.hint")
                Toggle("smb.field.performance_analysis", isOn: $settings.performanceAnalysis)
                    .accessibilityHint("smb.field.performance_analysis.hint")
            }

            Section("smb.section.compatibility") {
                Toggle("smb.field.ntlmv1", isOn: $settings.ntlmv1Authentication)
                    .accessibilityHint("smb.field.ntlmv1.hint")
                Toggle("smb.field.single_connection_per_ip", isOn: $settings.resetsOnZeroVirtualCircuit)
                    .accessibilityHint("smb.field.single_connection_per_ip.hint")
                Toggle("smb.field.debug_log", isOn: $settings.debugLogging)
                    .accessibilityHint("smb.field.debug_log.hint")
            }
        }
        .formStyle(.grouped)
        .accessibilityLabel("smb.advanced.form.label")
    }
}
