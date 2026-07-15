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
                    title: "Aucun stockage détecté",
                    systemImage: "internaldrive",
                    description: "DSM n’a renvoyé aucun volume ni disque."
                )
                .accessibilityFocused($focusContent)
            } else {
                List {
                    ForEach(vm.pools) { poolSection($0) }
                    ForEach(vm.volumes) { volumeSection($0) }
                    ForEach(vm.disks) { diskSection($0) }
                }
                .accessibilityFocused($focusContent)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await load() }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }
                .help("Actualiser l’état du stockage")
            }
        }
        .task { await load(restoresInitialFocus: true) }
    }

    private func poolSection(_ pool: StoragePool) -> some View {
        Section {
            LabeledContent("État", value: pool.statusText)
            LabeledContent("Type RAID", value: pool.raidTypeText)
            LabeledContent("Disques", value: pool.diskCountText)
            if let size = pool.sizeText {
                LabeledContent("Capacité", value: size)
            }
        } header: {
            Label(pool.displayName, systemImage: "externaldrive.connected.to.line.below")
        }
    }

    private func volumeSection(_ volume: Volume) -> some View {
        Section {
            LabeledContent("État", value: volume.statusText)
            LabeledContent("Système de fichiers", value: volume.filesystemText)
            if let space = volume.spaceText {
                LabeledContent("Espace", value: space)
            }
            if let percent = volume.usagePercentValue {
                LabeledContent("Utilisation", value: "\(percent) %")
            }
            if let operation = volume.operationText {
                LabeledContent("Opération", value: operation)
            }
            if let inodes = volume.inodePercent {
                LabeledContent("Inodes utilisés", value: "\(inodes) %")
            }
        } header: {
            Label(volume.displayName, systemImage: "internaldrive")
        }
    }

    private func diskSection(_ disk: Disk) -> some View {
        Section {
            LabeledContent("Santé", value: disk.healthText)
            if let temperature = disk.temperatureText {
                LabeledContent("Température", value: temperature)
            }
            if let size = disk.sizeText {
                LabeledContent("Capacité", value: size)
            }
            if let badSectors = disk.uncText {
                LabeledContent("Avertissement", value: badSectors)
            }
        } header: {
            Label(disk.displayName, systemImage: "internaldrive")
        }
    }

    private func load(restoresInitialFocus: Bool = false) async {
        VoiceOver.announce(
            String(localized: "Chargement du stockage…"),
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
