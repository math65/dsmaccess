//
//  FileStationVirtualFoldersView.swift
//  dsmaccess
//
//  Browsing the NFS, CIFS and ISO mounts announced by File Station.
//

import SwiftUI

struct FileStationVirtualFoldersView: View {
    @Bindable var vm: FileBrowserViewModel
    let open: (FileStationItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType = FileStationVirtualFolderType.cifs
    @State private var sort = FileStationListSort.name
    @State private var ascending = true
    @State private var selection = Set<FileStationItem.ID>()
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
                    .foregroundStyle(.readableRed)
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
            // No sortable columns: the sort is the one the picker above asks DSM for, and it
            // covers fields this table does not show (owner, group, POSIX, dates). Sorting by
            // header would silently override the choice the user just made.
            Table(vm.virtualFolders, selection: $selection) {
                TableColumn("common.column.name") { folder in
                    Text(folder.name)
                }
                TableColumn("common.column.location") { folder in
                    Text(folder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TableColumn("common.column.free_space") { folder in
                    Text(folder.freeSpaceDescription)
                }
                TableColumn("common.column.access") { folder in
                    Text(folder.volumeAccessDescription)
                }
            }
            .accessibilityLabel("virtual_folders.table.label")
            .contextMenu(forSelectionType: FileStationItem.ID.self) { ids in
                if let folder = vm.virtualFolders.first(where: { ids.contains($0.id) }) {
                    Button("common.button.open") {
                        open(folder)
                        dismiss()
                    }
                }
            }
        }
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
