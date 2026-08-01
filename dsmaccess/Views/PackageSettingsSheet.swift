//
//  PackageSettingsSheet.swift
//  dsmaccess
//
//  Sheet for the global Package Center settings (SYNO.Core.Package.Setting): automatic
//  updates, beta packages, notifications. Each control saves immediately (like the toggles
//  in FileServicesView) and announces the result to VoiceOver.
//

import SwiftUI

struct PackageSettingsSheet: View {
    @State private var vm: PackageSettingsViewModel
    @State private var showPackageSources = false
    @AccessibilityFocusState private var focusTitle: Bool
    @AccessibilityFocusState private var focusStatus: Bool
    @Environment(\.dismiss) private var dismiss

    private let session: SessionStore
    private let canManagePackageSources: Bool

    init(session: SessionStore, canManagePackageSources: Bool) {
        self.session = session
        self.canManagePackageSources = canManagePackageSources
        _vm = State(initialValue: PackageSettingsViewModel(session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("packages.settings.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)

            content

            if let error = vm.saveErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.readableRed)
                    .accessibilityFocused($focusStatus)
            }

            if vm.isSaving {
                ProgressView("packages.settings.saving.progress")
            }

            HStack {
                Spacer()
                Button("common.status.done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.isSaving)
                    .help("packages.settings.close.hint")
            }
        }
        .padding(24)
        .frame(width: 460)
        .task {
            focusTitle = true
            await load()
        }
        .sheet(isPresented: $showPackageSources) {
            PackageSourcesSheet(session: session)
        }
        .interactiveDismissDisabled(vm.isSaving)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.settings == nil {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("common.status.loading").foregroundStyle(.readableSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityFocused($focusStatus)
        } else if let error = vm.errorMessage, vm.settings == nil {
            VStack(alignment: .leading, spacing: 12) {
                Text(error).foregroundStyle(.readableRed)
                Button("common.button.retry") { Task { await load() } }
                    .help("packages.settings.retry.button")
            }
            .accessibilityFocused($focusStatus)
        } else if vm.settings != nil {
            controls
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Automatic updates.
            VStack(alignment: .leading, spacing: 4) {
                Picker("packages.settings.automatic_updates", selection: autoUpdateBinding) {
                    Text("common.status.disabled.feminine").tag(AutoUpdateMode.off)
                    Text("packages.settings.update_scope.important").tag(AutoUpdateMode.important)
                    Text("packages.settings.update_scope.latest").tag(AutoUpdateMode.latest)
                }
                .help("packages.settings.automatic_updates.hint")
                Text("packages.settings.auto_update.footer")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Beta packages.
            VStack(alignment: .leading, spacing: 4) {
                Toggle("packages.settings.beta_versions.label", isOn: boolBinding(
                    get: { $0.updateChannelBeta },
                    set: { await vm.setBeta($0) }
                ))
                .help("packages.settings.beta_versions.hint")
                Text("packages.settings.beta.description")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Notifications.
            VStack(alignment: .leading, spacing: 8) {
                Text("packages.settings.update_notifications.section")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Toggle("packages.settings.desktop_notifications", isOn: boolBinding(
                    get: { $0.enableDsm },
                    set: { await vm.setDsmNotify($0) }
                ))
                .help("packages.settings.desktop_notifications.hint")
                Toggle("packages.settings.email_notification.label", isOn: boolBinding(
                    get: { $0.enableEmail },
                    set: { await vm.setEmailNotify($0) }
                ))
                .help("packages.settings.email_notification.hint")
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("packages.settings.preserved_settings.label")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                if let settings = vm.settings {
                    LabeledContent("packages.settings.default_volume", value: settings.defaultVol)
                    LabeledContent("packages.settings.trust_level.label") {
                        Text(settings.trustLevel, format: .number.grouping(.never))
                    }
                }
                Text("packages.settings.trust_level.description")
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if canManagePackageSources {
                    Button("packages.settings.manage_sources.button") {
                        showPackageSources = true
                    }
                    .help("packages.settings.sources.hint")
                } else {
                    Text("packages.settings.manage_sources.unavailable")
                        .font(.caption)
                        .foregroundStyle(.readableSecondary)
                }
            }
        }
        .disabled(vm.isSaving)
    }

    // MARK: - Bindings

    private var autoUpdateBinding: Binding<AutoUpdateMode> {
        Binding(
            get: { vm.settings?.autoUpdateMode ?? .off },
            set: { mode in
                Task {
                    let msg = await vm.setAutoUpdateMode(mode)
                    VoiceOver.announce(msg, priority: .high)
                }
            }
        )
    }

    /// Builds a Binding<Bool> that reads a settings field and saves through `set`.
    private func boolBinding(get: @escaping (PackageSettings) -> Bool,
                             set: @escaping (Bool) async -> DSMOperationOutcome) -> Binding<Bool> {
        Binding(
            get: { vm.settings.map(get) ?? false },
            set: { newValue in
                Task {
                    let msg = await set(newValue)
                    VoiceOver.announce(msg, priority: .high)
                }
            }
        )
    }

    private var loadAnnouncement: String {
        if let error = vm.errorMessage { return error }
        return String(localized: "packages.settings.loaded.announcement")
    }

    private func load() async {
        await vm.load()
        guard !Task.isCancelled else { return }
        if vm.errorMessage != nil { focusStatus = true }
        VoiceOver.announce(
            loadAnnouncement,
            category: vm.errorMessage == nil ? .result : .error
        )
    }
}
