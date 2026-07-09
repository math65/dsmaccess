//
//  StorageView.swift
//  dsmaccess
//
//  Module « Stockage » : volumes (espace, système de fichiers, statut) et disques (modèle,
//  température, santé). Lecture seule. Chaque carte est un élément VoiceOver combiné.
//

import SwiftUI

struct StorageView: View {
    @State private var vm: StorageViewModel
    @AccessibilityFocusState private var focusTitle: Bool

    init(session: SessionStore) {
        _vm = State(initialValue: StorageViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Stockage")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusTitle)

                content
            }
            .padding(28)
            .frame(maxWidth: 540, alignment: .leading)
        }
        .task {
            focusTitle = true
            await vm.load()
            AccessibilityNotification.Announcement(vm.summary).post()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.info == nil {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Chargement…").foregroundStyle(.secondary)
            }
        } else if let error = vm.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
                Text(error).foregroundStyle(.red)
                Button("Réessayer") {
                    Task { await vm.load(); AccessibilityNotification.Announcement(vm.summary).post() }
                }
            }
        } else {
            if !vm.volumes.isEmpty {
                section("Volumes") {
                    ForEach(vm.volumes) { volumeCard($0) }
                }
            }
            if !vm.disks.isEmpty {
                section("Disques") {
                    ForEach(vm.disks) { diskCard($0) }
                }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func volumeCard(_ volume: Volume) -> some View {
        card {
            Text(volume.displayName).fontWeight(.medium)
            row("État", volume.statusText)
            row("Système de fichiers", volume.filesystemText)
            if let space = volume.spaceText { row("Espace", space) }
            if let percent = volume.usagePercent {
                row("Utilisation", "\(percent) %")
            }
        }
    }

    private func diskCard(_ disk: Disk) -> some View {
        card {
            Text(disk.displayName).fontWeight(.medium)
            row("Santé", disk.healthText)
            if let temp = disk.temperatureText { row("Température", temp) }
            if let size = disk.sizeText { row("Capacité", size) }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
