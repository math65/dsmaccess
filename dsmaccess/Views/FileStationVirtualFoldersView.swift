//
//  FileStationVirtualFoldersView.swift
//  dsmaccess
//
//  Navigation dans les montages NFS, CIFS et ISO annoncés par File Station.
//

import SwiftUI

struct FileStationVirtualFoldersView: View {
    @Bindable var vm: FileBrowserViewModel
    let open: (FileStationItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType = FileStationVirtualFolderType.cifs
    @State private var sort = FileStationListSort.name
    @State private var ascending = true
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusStatus: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button("common.button.close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 720, height: 520)
        .task {
            if !vm.availableVirtualFolderTypes.contains(selectedType),
               let first = vm.availableVirtualFolderTypes.first {
                selectedType = first
            } else {
                await load()
            }
        }
        .onChange(of: selectedType) { _, _ in Task { await load() } }
    }

    private var header: some View {
        HStack {
            Text("virtual_folders.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusHeading)
            Spacer()
            if vm.isLoadingVirtualFolders {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("virtual_folders.loading")
            }
            Button("common.button.close", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("common.column.protocol", selection: $selectedType) {
                ForEach(vm.availableVirtualFolderTypes) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .frame(maxWidth: 180)
            Picker("common.label.sort_by", selection: $sort) {
                ForEach(FileStationListSort.allCases, id: \.self) { value in
                    Text(value.localizedTitle).tag(value)
                }
            }
            .frame(maxWidth: 230)
            Toggle("common.sort.ascending", isOn: $ascending)
            Button("common.button.apply") { Task { await load() } }
                .disabled(vm.isLoadingVirtualFolders)
            Spacer()
            Button("common.button.refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                .disabled(vm.isLoadingVirtualFolders)
                .help("virtual_folders.refresh.label")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if vm.availableVirtualFolderTypes.isEmpty {
            ContentUnavailableView(
                "virtual_folders.empty",
                systemImage: "externaldrive.badge.questionmark",
                description: Text("virtual_folders.empty.description")
            )
            .accessibilityFocused($focusStatus)
        } else if vm.isLoadingVirtualFolders && vm.virtualFolders.isEmpty {
            ModuleLoadingView("virtual_folders.loading")
                .accessibilityFocused($focusStatus)
        } else if let error = vm.virtualFoldersError {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("common.button.retry") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if vm.virtualFolders.isEmpty {
            ContentUnavailableView(
                String(localized: "virtual_folders.protocol.empty", defaultValue: "No \(selectedType.displayName) folders"),
                systemImage: "externaldrive",
                description: Text("virtual_folders.protocol.empty.description")
            )
            .accessibilityFocused($focusStatus)
        } else {
            List(vm.virtualFolders) { folder in
                virtualFolderRow(folder)
            }
            .accessibilityLabel("virtual_folders.table.label")
        }
    }

    private func virtualFolderRow(_ folder: FileStationItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let summary = volumeSummary(folder.additional?.volumeStatus) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("common.button.open", systemImage: "arrow.forward") {
                open(folder)
                dismiss()
            }
            .help("virtual_folders.open.label")
        }
        .accessibilityElement(children: .contain)
    }

    private func load() async {
        guard vm.availableVirtualFolderTypes.contains(selectedType) else {
            focusStatus = true
            return
        }
        await vm.loadVirtualFolders(
            type: selectedType,
            options: FileStationListOptions(
                sortBy: sort,
                sortDirection: ascending ? .ascending : .descending
            )
        )
        guard !Task.isCancelled else { return }
        if let error = vm.virtualFoldersError {
            focusStatus = true
            VoiceOver.announce(error, category: .error, priority: .high)
        } else {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "virtual_folders.count", defaultValue: "Virtual folders: \(vm.virtualFolders.count)"),
                category: .result
            )
        }
    }

    private func volumeSummary(_ volume: FileStationItem.VolumeStatus?) -> String? {
        guard let volume else { return nil }
        var parts = [String]()
        if let freeSpace = volume.freeSpace {
            parts.append(
                String(localized: "virtual_folders.free_space", defaultValue: "Free: \(freeSpace.formatted(.byteCount(style: .file)))")
            )
        }
        if volume.isReadOnly == true {
            parts.append(String(localized: "common.permission.read_only"))
        }
        return parts.isEmpty ? nil : parts.formatted(.list(type: .and))
    }
}

private extension FileStationVirtualFolderType {
    var displayName: String { rawValue.uppercased() }
}

private extension FileStationListSort {
    var localizedTitle: String {
        switch self {
        case .name: String(localized: "common.column.name")
        case .size: String(localized: "common.column.size")
        case .user: String(localized: "common.column.owner")
        case .group: String(localized: "common.column.group")
        case .modifiedTime: String(localized: "common.column.date_modified")
        case .accessedTime: String(localized: "virtual_folders.column.access_date")
        case .changedTime: String(localized: "virtual_folders.column.change_date")
        case .createdTime: String(localized: "common.column.creation_date")
        case .posix: "POSIX"
        case .type: String(localized: "common.column.kind")
        }
    }
}
