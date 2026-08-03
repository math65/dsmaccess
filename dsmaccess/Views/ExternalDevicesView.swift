//
//  ExternalDevicesView.swift
//  dsmaccess
//
//  Control Panel section for USB and eSATA storage.
//

import SwiftUI

struct ExternalDevicesView: View {
    /// Owned by `MainView`, which also drives the toolbar menu: two view models would drift
    /// apart, and the menu would keep offering a device this screen has already ejected.
    let model: ExternalDevicesViewModel

    @State private var selection: ExternalStorageDevice.ID?
    @State private var deviceToFormat: ExternalStorageDevice?
    @State private var isConfirmingUSBLock = false
    @AccessibilityFocusState private var focusesOutcome: Bool
    @AccessibilityFocusState private var focusesDevices: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let outcome = model.lastOutcome {
                outcomeBanner(outcome)
            }
            devicesSection
            if let device = selectedDevice {
                partitionsSection(of: device)
            }
            settingsSection
        }
        .padding(20)
        .navigationTitle("external_devices.title")
        .task {
            await model.load()
            focusesDevices = true
        }
        .task(id: model.isFormattingAnyDevice) {
            await model.followFormatting()
        }
        .sheet(item: $deviceToFormat) { device in
            ExternalDeviceFormatSheet(device: device) { fileSystem in
                Task { await model.format(device, as: fileSystem) }
            }
        }
        .alert(
            "module.error.title",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("common.button.ok", role: .cancel) { model.errorMessage = nil }
            Button("common.button.retry") { Task { await model.load(announcesResult: true) } }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Devices

    @ViewBuilder
    private var devicesSection: some View {
        if model.isLoading && !model.hasDevices {
            ProgressView("external_devices.loading.progress")
                .controlSize(.small)
        } else if !model.hasDevices {
            ContentUnavailableView(
                "external_devices.empty.title",
                systemImage: "externaldrive",
                description: Text("external_devices.empty.description")
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Table(model.devices, selection: $selection) {
                TableColumn("external_devices.column.name") { device in
                    Text(device.displayName)
                }
                TableColumn("external_devices.column.connection") { device in
                    Text(device.connection.title)
                }
                TableColumn("external_devices.column.maker") { device in
                    Text(device.producer ?? "—")
                }
                TableColumn("external_devices.column.model") { device in
                    Text(device.product ?? "—")
                }
                TableColumn("external_devices.column.capacity") { device in
                    Text(Self.size(ofMegabytes: device.totalSizeMB))
                }
                TableColumn("external_devices.column.status") { device in
                    Text(device.statusText)
                        .foregroundStyle(device.isFormatting ? .readableOrange : .readableSecondary)
                }
            }
            .accessibilityLabel("external_devices.table.label")
            .accessibilityFocused($focusesDevices)
            .frame(minHeight: 140)
            .contextMenu(forSelectionType: ExternalStorageDevice.ID.self) { identifiers in
                deviceActions(for: identifiers)
            }
        }
    }

    /// Every action stays listed whatever the selection, disabled when it cannot apply, so the
    /// menu keeps the same shape from one row to the next.
    @ViewBuilder
    private func deviceActions(for identifiers: Set<ExternalStorageDevice.ID>) -> some View {
        let device = identifiers.count == 1
            ? model.devices.first { $0.devID == identifiers.first }
            : nil
        let isBusy = device.map(model.isBusy) ?? true
        Button("external_devices.action.eject") {
            guard let device else { return }
            Task { await model.eject(device) }
        }
        .disabled(isBusy)
        Button("external_devices.action.format", role: .destructive) {
            deviceToFormat = device
        }
        .disabled(isBusy || device?.isFormattable != true)
        Divider()
        Button("common.button.refresh") {
            Task { await model.load(announcesResult: true) }
        }
    }

    // MARK: - Partitions

    private func partitionsSection(of device: ExternalStorageDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                String(
                    localized: "external_devices.partitions.title",
                    defaultValue: "Partitions of \(device.displayName)"
                )
            )
            .font(.headline)
            .accessibilityAddTraits(.isHeader)

            if device.partitions.isEmpty {
                Text("external_devices.partitions.none")
                    .foregroundStyle(.readableSecondary)
            } else {
                Table(device.partitions) {
                    TableColumn("external_devices.column.name") { partition in
                        Text(partition.displayName)
                    }
                    TableColumn("external_devices.column.shared_folder") { partition in
                        Text(partition.shareName ?? "—")
                    }
                    TableColumn("external_devices.column.filesystem") { partition in
                        Text(partition.filesystem ?? "—")
                    }
                    TableColumn("external_devices.column.used") { partition in
                        Text(Self.size(ofMegabytes: partition.usedSizeMB))
                    }
                    TableColumn("external_devices.column.capacity") { partition in
                        Text(Self.size(ofMegabytes: partition.totalSizeMB))
                    }
                }
                .accessibilityLabel("external_devices.partitions.table.label")
                .frame(minHeight: 100)
            }
        }
    }

    // MARK: - Settings

    @ViewBuilder
    private var settingsSection: some View {
        if let settings = model.settings {
            Text("external_devices.settings.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Form {
                Section {
                    // Locking the USB port cuts off every device and needs a restart: too
                    // costly to happen on a mistaken space bar, so it asks first.
                    Toggle(
                        "external_devices.settings.forbid_usb.label",
                        isOn: Binding(
                            get: { settings.forbidsUSB },
                            set: { isForbidden in
                                if isForbidden {
                                    isConfirmingUSBLock = true
                                } else {
                                    apply(settings, keyPath: \.forbidsUSB, value: false)
                                }
                            }
                        )
                    )
                    .help("external_devices.settings.forbid_usb.hint")
                    Text("external_devices.settings.forbid_usb.description")
                        .font(.caption)
                        .foregroundStyle(.readableSecondary)

                    Toggle(
                        "external_devices.settings.non_admin_eject.label",
                        isOn: binding(for: settings, keyPath: \.allowsNonAdminEject)
                    )
                    .help("external_devices.settings.non_admin_eject.hint")

                    Toggle(
                        "external_devices.settings.delayed_allocation.label",
                        isOn: binding(for: settings, keyPath: \.usesDelayedAllocation)
                    )
                    .help("external_devices.settings.delayed_allocation.hint")
                    Text("external_devices.settings.delayed_allocation.description")
                        .font(.caption)
                        .foregroundStyle(.readableSecondary)

                    if settings.needsReboot {
                        Text("external_devices.settings.reboot_required")
                            .foregroundStyle(.readableOrange)
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel("external_devices.settings.region.label")
            .disabled(model.isSavingSettings)
            .frame(maxHeight: 320)
            .confirmationDialog(
                "external_devices.settings.forbid_usb.confirm.title",
                isPresented: $isConfirmingUSBLock,
                titleVisibility: .visible
            ) {
                Button("external_devices.settings.forbid_usb.confirm.button", role: .destructive) {
                    apply(settings, keyPath: \.forbidsUSB, value: true)
                }
                Button("common.button.cancel", role: .cancel) { }
            } message: {
                Text("external_devices.settings.forbid_usb.confirm.message")
            }
        }
    }

    private func binding(
        for settings: ExternalStorageSettings,
        keyPath: WritableKeyPath<ExternalStorageSettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in apply(settings, keyPath: keyPath, value: newValue) }
        )
    }

    private func apply(
        _ settings: ExternalStorageSettings,
        keyPath: WritableKeyPath<ExternalStorageSettings, Bool>,
        value: Bool
    ) {
        var updated = settings
        updated[keyPath: keyPath] = value
        Task { await model.updateSettings(updated) }
    }

    // MARK: - Outcome

    private func outcomeBanner(_ outcome: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(outcome)
                .accessibilityFocused($focusesOutcome)
            Spacer()
            Button("external_devices.outcome.dismiss.button", action: model.dismissOutcome)
                .help("external_devices.outcome.dismiss.hint")
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 8))
        .onAppear { focusesOutcome = true }
    }

    private var selectedDevice: ExternalStorageDevice? {
        guard let selection else { return nil }
        return model.devices.first { $0.devID == selection }
    }

    private static func size(ofMegabytes megabytes: Int?) -> String {
        guard let megabytes else { return "—" }
        return Measurement(value: Double(megabytes), unit: UnitInformationStorage.megabytes)
            .formatted(.byteCount(style: .file))
    }
}
