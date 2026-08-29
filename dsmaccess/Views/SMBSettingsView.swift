//
//  SMBSettingsView.swift
//  dsmaccess
//
//  The SMB tab of the file services: every setting DSM offers for the protocol Finder and
//  Windows Explorer use.
//
//  Settings are edited then applied together. The NAS restarts Samba on each write, so a
//  screen that applied field by field would cut the shares once per switch.
//

import SwiftUI

struct SMBSettingsPane: View {
    /// Owned by the screen around it, so its toolbar can reload the visible tab.
    @Bindable var vm: SMBSettingsViewModel
    @AccessibilityFocusState private var focusContent: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        content
            .task { await load(restoresInitialFocus: true) }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.applied == nil {
            ModuleLoadingView("smb.loading")
                .accessibilityFocused($focusContent)
        } else if let settings = Binding($vm.draft) {
            VStack(spacing: 0) {
                SMBSettingsForm(settings: settings, logsTransfers: $vm.draftLogsTransfers)
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

/// The form itself. Split out so the surrounding screen keeps its loading, error and action
/// states readable, and so the bindings are non-optional here.
private struct SMBSettingsForm: View {
    @Binding var settings: SMBSettings
    @Binding var logsTransfers: Bool

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

            Section("smb.section.protocol") {
                Picker("smb.field.min_protocol", selection: $settings.advanced.minimumProtocol) {
                    ForEach(SMBProtocolVersion.minimumChoices) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                .accessibilityHint("smb.field.min_protocol.hint")
                Picker("smb.field.max_protocol", selection: $settings.advanced.maximumProtocol) {
                    ForEach(SMBProtocolVersion.maximumChoices) { version in
                        Text(version.displayName).tag(version)
                    }
                }
                .accessibilityHint("smb.field.max_protocol.hint")
                Picker("smb.field.encryption", selection: $settings.advanced.transportEncryption) {
                    ForEach(SMBTransportEncryption.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityHint("smb.field.encryption.hint")
                Picker("smb.field.signing", selection: $settings.advanced.serverSigning) {
                    ForEach(SMBServerSigning.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityHint("smb.field.signing.hint")
                TextField("smb.field.wins", text: $settings.advanced.winsServer)
                    .accessibilityHint("smb.field.wins.hint")
            }
            .disabled(isServiceOff)

            Section("smb.section.locking") {
                Toggle("smb.field.op_lock", isOn: $settings.advanced.opportunisticLocking)
                    .accessibilityHint("smb.field.op_lock.hint")
                Toggle("smb.field.smb2_leases", isOn: $settings.advanced.smb2FileLeases)
                    .disabled(!settings.advanced.opportunisticLocking)
                Toggle("smb.field.smb3_directory_leasing", isOn: $settings.advanced.smb3DirectoryLeasing)
                    .disabled(!settings.advanced.opportunisticLocking || !settings.advanced.smb2FileLeases)
                Toggle("smb.field.durable_handles", isOn: $settings.advanced.durableHandles)
                    .accessibilityHint("smb.field.durable_handles.hint")
                if !settings.advanced.opportunisticLocking {
                    Text("smb.locking.requires_op_lock")
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)
                }
            }
            .disabled(isServiceOff)

            Section("smb.section.macos") {
                Toggle("smb.field.mac_characters", isOn: $settings.advanced.macCharacterConversion)
                    .accessibilityHint("smb.field.mac_characters.hint")
                Toggle("smb.field.afp_cross_locking", isOn: $settings.advanced.crossProtocolLockingWithAFP)
                    .accessibilityHint("smb.field.afp_cross_locking.hint")
            }
            .disabled(isServiceOff)

            Section("smb.section.other") {
                Toggle("smb.field.local_master_browser", isOn: $settings.advanced.localMasterBrowser)
                Toggle("smb.field.dirsort", isOn: $settings.advanced.directorySorting)
                    .accessibilityHint("smb.field.dirsort.hint")
                Toggle("smb.field.symlinks", isOn: $settings.advanced.symbolicLinks)
                Toggle("smb.field.wide_links", isOn: $settings.advanced.wideLinks)
                    .disabled(!settings.advanced.symbolicLinks)
                Toggle("smb.field.single_connection_per_ip", isOn: $settings.advanced.resetsOnZeroVirtualCircuit)
                Toggle("smb.field.debug_log", isOn: $settings.advanced.debugLogging)
                    .accessibilityHint("smb.field.debug_log.hint")
                Toggle("smb.field.unix_permissions", isOn: $settings.advanced.defaultUnixPermissions)
                Toggle("smb.field.skip_allocation", isOn: $settings.advanced.skipsDiskAllocation)
                Toggle("smb.field.ntlmv1", isOn: $settings.advanced.ntlmv1Authentication)
                    .accessibilityHint("smb.field.ntlmv1.hint")
                Toggle("smb.field.async_read", isOn: $settings.advanced.asynchronousRead)
                Toggle("smb.field.subfolder_notification", isOn: $settings.advanced.subfolderChangeNotification)
                Toggle("smb.field.immediate_sync", isOn: $settings.advanced.immediateSync)
                    .accessibilityHint("smb.field.immediate_sync.hint")
                Toggle("smb.field.multichannel", isOn: $settings.advanced.smb3Multichannel)
                Toggle("smb.field.wildcard_cache", isOn: $settings.advanced.wildcardSearchCache)
                Toggle("smb.field.performance_analysis", isOn: $settings.advanced.performanceAnalysis)
            }
            .disabled(isServiceOff)
        }
        .formStyle(.grouped)
        .accessibilityLabel("smb.form.label")
    }
}
