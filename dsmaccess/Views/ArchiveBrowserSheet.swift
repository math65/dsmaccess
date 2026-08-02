//
//  ArchiveBrowserSheet.swift
//  dsmaccess
//
//  Browsing and selective extraction of the contents of a File Station archive.
//

import SwiftUI

struct ArchiveBrowserSheet: View {
    private struct Level: Equatable {
        let name: String
        let itemID: Int?
    }

    @Bindable var vm: FileBrowserViewModel
    let archive: FileStationItem
    let onExtract: (FileStationExtractionOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var levels = [Level(name: String(localized: "files.archive.path.root"), itemID: nil)]
    @State private var selection = Set<Int>()
    @State private var sort = FileStationArchiveSort.name
    @State private var ascending = true
    @State private var usesCodepage = false
    @State private var codepage = FileStationArchiveCodepage.french
    @State private var password = ""
    @State private var showingExtractionOptions = false
    @AccessibilityFocusState private var focusHeading: Bool
    @AccessibilityFocusState private var focusStatus: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            optionsBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 760, height: 650)
        .task {
            focusHeading = true
            await load()
        }
        .onDisappear { vm.clearArchive() }
        .sheet(isPresented: $showingExtractionOptions) {
            FileExtractionOptionsSheet(
                archiveName: archive.name,
                itemIDs: Array(selection).sorted(),
                initialCodepage: usesCodepage ? codepage : nil,
                initialPassword: password
            ) { options in
                onExtract(options)
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("common.button.parent_folder", systemImage: "chevron.up", action: goUp)
                .disabled(levels.count == 1 || vm.isLoadingArchive)
                .help("files.archive.button.parent_folder.hint")
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "files.archive.contents_of.title", defaultValue: "Contents of \(archive.name)"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusHeading)
                Text(levels.map(\.name).joined(separator: " ▸ "))
                    .font(.caption)
                    .foregroundStyle(.readableSecondary)
            }
            Spacer()
            Button("common.button.refresh", systemImage: "arrow.clockwise") {
                Task { await load() }
            }
            .disabled(vm.isLoadingArchive)
            .help("files.archive.button.reload.hint")
        }
        .padding()
    }

    private var optionsBar: some View {
        Form {
            HStack(alignment: .top, spacing: 16) {
                SecureField("common.field.optional_password", text: $password)
                    .frame(maxWidth: 240)
                Toggle("files.archive.encoding.label", isOn: $usesCodepage)
                if usesCodepage {
                    Picker("common.field.encoding", selection: $codepage) {
                        ForEach(FileStationArchiveCodepage.allCases) { value in
                            Text(value.localizedTitle).tag(value)
                        }
                    }
                    .frame(maxWidth: 190)
                }
            }
            HStack(spacing: 16) {
                Picker("common.label.sort_by", selection: $sort) {
                    ForEach(FileStationArchiveSort.allCases, id: \.self) { value in
                        Text(value.localizedTitle).tag(value)
                    }
                }
                .frame(maxWidth: 220)
                Toggle("common.sort.ascending", isOn: $ascending)
                Button("common.button.apply") { Task { await load() } }
                    .disabled(vm.isLoadingArchive)
            }
        }
        .formStyle(.grouped)
        .accessibilityLabel("files.archive.options.label")
        .frame(height: 155)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingArchive && vm.archiveItems.isEmpty {
            ModuleLoadingView("files.archive.loading.label")
                .accessibilityFocused($focusStatus)
        } else if let error = vm.archiveError {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.readableRed)
                    .multilineTextAlignment(.center)
                Text("files.archive.read_failed.hint")
                    .foregroundStyle(.readableSecondary)
                Button("common.button.retry") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityFocused($focusStatus)
        } else if vm.archiveItems.isEmpty {
            ContentUnavailableView(
                "files.archive.folder.empty",
                systemImage: "archivebox",
                description: Text("files.archive.empty")
            )
            .accessibilityFocused($focusStatus)
        } else {
            // No sortable columns: the sort is the one the controls above ask DSM for, and
            // sorting by header would silently override the choice the user just made.
            Table(vm.archiveItems, selection: $selection) {
                TableColumn("common.column.name") { item in
                    Text(item.name)
                }
                TableColumn("common.column.kind") { item in
                    Text(item.kindDescription)
                }
                TableColumn("common.column.size") { item in
                    Text(item.size, format: .byteCount(style: .file))
                }
                TableColumn("files.archive.column.compressed_size") { item in
                    Text(item.packedSize, format: .byteCount(style: .file))
                }
                TableColumn("common.column.date_modified") { item in
                    Text(item.modificationTime)
                }
            }
            .accessibilityLabel("files.archive.title")
            .contextMenu(forSelectionType: FileStationArchiveItem.ID.self) { ids in
                if let item = vm.archiveItems.first(where: { ids.contains($0.itemID) && $0.isDirectory }) {
                    Button("common.button.open") { open(item) }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("files.archive.button.select_all") {
                selection.formUnion(vm.archiveItems.map(\.itemID))
            }
            .disabled(vm.archiveItems.isEmpty)
            Button("files.archive.button.clear_selection") { selection.removeAll() }
                .disabled(selection.isEmpty)
            Spacer()
            Button("common.button.cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                showingExtractionOptions = true
            } label: {
                Text(
                    selection.isEmpty
                        ? String(localized: "files.archive.button.extract_all")
                        : String(localized: "files.archive.button.extract_selection")
                )
            }
            .disabled(vm.isLoadingArchive || vm.archiveError != nil)
            .keyboardShortcut(.defaultAction)
            .help(selection.isEmpty
                  ? String(localized: "files.archive.button.extract_all.hint")
                  : String(localized: "files.archive.button.extract_selection.hint"))
        }
        .padding()
    }

    private func load() async {
        VoiceOver.announce(
            String(localized: "files.archive.loading.announcement"),
            category: .progress,
            priority: .low
        )
        await vm.loadArchive(
            archive,
            options: FileStationArchiveListOptions(
                sortBy: sort,
                sortDirection: ascending ? .ascending : .descending,
                codepage: usesCodepage ? codepage : nil,
                password: password.isEmpty ? nil : password,
                parentItemID: levels.last?.itemID
            )
        )
        guard !Task.isCancelled else { return }
        if let error = vm.archiveError {
            focusStatus = true
            VoiceOver.announce(error, category: .error, priority: .high)
        } else {
            focusHeading = true
            VoiceOver.announce(
                String(localized: "files.archive.folder.item_count", defaultValue: "Items in this folder: \(vm.archiveItems.count)"),
                category: .result
            )
        }
    }

    private func open(_ item: FileStationArchiveItem) {
        guard item.isDirectory else { return }
        levels.append(Level(name: item.name, itemID: item.itemID))
        Task { await load() }
    }

    private func goUp() {
        guard levels.count > 1 else { return }
        levels.removeLast()
        Task { await load() }
    }
}

private extension FileStationArchiveSort {
    var localizedTitle: String {
        switch self {
        case .name: String(localized: "common.column.name")
        case .size: String(localized: "files.archive.column.original_size")
        case .packedSize: String(localized: "files.archive.column.compressed_size")
        case .modifiedTime: String(localized: "common.column.date_modified")
        }
    }
}
