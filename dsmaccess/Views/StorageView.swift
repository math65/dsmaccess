//
//  StorageView.swift
//  dsmaccess
//
//  State of the storage pools, volumes and disks.
//

import SwiftUI

struct StorageView: View {
    @State private var vm: StorageViewModel
    @State private var poolOrder = [KeyPathComparator(\StoragePool.displayName, order: .forward)]
    @State private var volumeOrder = [KeyPathComparator(\Volume.displayName, order: .forward)]
    @State private var diskOrder = [KeyPathComparator(\Disk.displayName, order: .forward)]
    @AccessibilityFocusState private var focusContent: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: StorageViewModel(session: session))
    }

    var body: some View {
        Group {
            if vm.isLoading && vm.info == nil {
                ModuleLoadingView()
                    .accessibilityFocused($focusContent)
            } else if let error = vm.errorMessage, vm.info == nil {
                ModuleErrorView(message: error) {
                    Task { await load() }
                }
                .accessibilityFocused($focusContent)
            } else if vm.pools.isEmpty && vm.volumes.isEmpty && vm.disks.isEmpty {
                EmptyModuleView(
                    title: "storage.empty.title",
                    systemImage: "internaldrive",
                    description: "storage.empty.description"
                )
                .accessibilityFocused($focusContent)
            } else {
                // Three tables and not one: a pool, a volume and a disk share no column, and
                // a single table would have to leave most cells empty on every row.
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !vm.pools.isEmpty { poolTable }
                        if !vm.volumes.isEmpty { volumeTable }
                        if !vm.disks.isEmpty { diskTable }
                    }
                    .padding(12)
                }
                .accessibilityLabel("storage.title")
                .accessibilityFocused($focusContent)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("common.button.refresh", systemImage: "arrow.clockwise")
                }
                .help("storage.refresh.button")
            }
        }
        .task { await load(restoresInitialFocus: true) }
    }

    private var poolTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("storage.pools.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Table(vm.pools.sorted(using: poolOrder), sortOrder: $poolOrder) {
                TableColumn("common.column.name", value: \.displayName) { pool in
                    Text(pool.displayName)
                }
                TableColumn("common.column.state", value: \.statusText) { pool in
                    Text(pool.statusText)
                }
                TableColumn("storage.pool.raid_type", value: \.raidTypeText) { pool in
                    Text(pool.raidTypeText)
                }
                TableColumn("common.label.disks", value: \.sortableDiskCount) { pool in
                    Text(pool.diskCountText)
                }
                TableColumn("common.column.capacity", value: \.sortableSize) { pool in
                    Text(pool.sizeText ?? "—")
                }
            }
            .accessibilityLabel("storage.pools.title")
            .frame(minHeight: 120)
        }
    }

    private var volumeTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("storage.volumes.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Table(vm.volumes.sorted(using: volumeOrder), sortOrder: $volumeOrder) {
                TableColumn("common.column.name", value: \.displayName) { volume in
                    Text(volume.displayName)
                }
                TableColumn("common.column.state", value: \.statusText) { volume in
                    Text(volume.statusText)
                }
                TableColumn("storage.volume.file_system", value: \.filesystemText) { volume in
                    Text(volume.filesystemText)
                }
                TableColumn("storage.volume.space", value: \.sortableSpace) { volume in
                    Text(volume.spaceText ?? "—")
                }
                TableColumn("common.column.usage", value: \.sortableUsage) { volume in
                    Text(volume.usagePercentValue.map { "\($0) %" } ?? "—")
                }
                TableColumn("storage.volume.inodes_used", value: \.sortableInodes) { volume in
                    Text(volume.inodePercent.map { "\($0) %" } ?? "—")
                }
                TableColumn("common.column.operation", value: \.sortableOperation) { volume in
                    Text(volume.operationText ?? "—")
                }
            }
            .accessibilityLabel("storage.volumes.title")
            .frame(minHeight: 120)
        }
    }

    private var diskTable: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("storage.disks.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Table(vm.disks.sorted(using: diskOrder), sortOrder: $diskOrder) {
                TableColumn("common.column.name", value: \.displayName) { disk in
                    Text(disk.displayName)
                }
                TableColumn("storage.disk.health", value: \.healthText) { disk in
                    Text(disk.healthText)
                }
                TableColumn("common.column.temperature", value: \.sortableTemperature) { disk in
                    Text(disk.temperatureText ?? "—")
                }
                TableColumn("common.column.capacity", value: \.sortableSize) { disk in
                    Text(disk.sizeText ?? "—")
                }
                // Named rather than left to a warning colour: a disk with no bad sector shows
                // a dash, and one with any shows how many.
                TableColumn("storage.disk.uncorrectable_sectors.column", value: \.sortableUncorrectableSectors) { disk in
                    Text(disk.uncText ?? "—")
                }
            }
            .accessibilityLabel("storage.disks.title")
            .frame(minHeight: 140)
        }
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "storage.loading"),
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
