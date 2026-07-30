//
//  StorageView.swift
//  dsmaccess
//
//  État des groupes de stockage, volumes et disques.
//

import SwiftUI

struct StorageView: View {
    @State private var vm: StorageViewModel
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
                List {
                    ForEach(vm.pools) { poolSection($0) }
                    ForEach(vm.volumes) { volumeSection($0) }
                    ForEach(vm.disks) { diskSection($0) }
                }
                .labeledContentStyle(.readable)
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

    private func poolSection(_ pool: StoragePool) -> some View {
        Section {
            LabeledContent("common.column.state", value: pool.statusText)
            LabeledContent("storage.pool.raid_type", value: pool.raidTypeText)
            LabeledContent("common.label.disks", value: pool.diskCountText)
            if let size = pool.sizeText {
                LabeledContent("common.column.capacity", value: size)
            }
        } header: {
            Label(pool.displayName, systemImage: "externaldrive.connected.to.line.below")
        }
    }

    private func volumeSection(_ volume: Volume) -> some View {
        Section {
            LabeledContent("common.column.state", value: volume.statusText)
            LabeledContent("storage.volume.file_system", value: volume.filesystemText)
            if let space = volume.spaceText {
                LabeledContent("storage.volume.space", value: space)
            }
            if let percent = volume.usagePercentValue {
                LabeledContent("common.column.usage", value: "\(percent) %")
            }
            if let operation = volume.operationText {
                LabeledContent("common.column.operation", value: operation)
            }
            if let inodes = volume.inodePercent {
                LabeledContent("storage.volume.inodes_used", value: "\(inodes) %")
            }
        } header: {
            Label(volume.displayName, systemImage: "internaldrive")
        }
    }

    private func diskSection(_ disk: Disk) -> some View {
        Section {
            LabeledContent("storage.disk.health", value: disk.healthText)
            if let temperature = disk.temperatureText {
                LabeledContent("common.column.temperature", value: temperature)
            }
            if let size = disk.sizeText {
                LabeledContent("common.column.capacity", value: size)
            }
            if let badSectors = disk.uncText {
                LabeledContent("common.level.warning", value: badSectors)
            }
        } header: {
            Label(disk.displayName, systemImage: "internaldrive")
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
