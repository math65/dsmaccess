//
//  OpenedFilesView.swift
//  dsmaccess
//
//  "Open files" tab of the resource monitor, as a sortable table like the module's other
//  tabs.
//
//  Read only. DSM can also close an open file, but its `kick` method kills the process
//  holding it — that is not a clean close, and the NAS only allows it for a handful of
//  services. That action remains to be scoped separately.
//

import SwiftUI

struct OpenedFilesView: View {
    @Bindable var vm: OpenedFilesViewModel
    @State private var order = [KeyPathComparator(\OpenedFile.sortableService)]
    @AccessibilityFocusState private var focusContent: Bool

    var body: some View {
        content
            .task {
                await vm.load()
                focusContent = true
            }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.files.isEmpty {
            ModuleLoadingView("opened_files.loading")
                .accessibilityFocused($focusContent)
        } else if let error = vm.errorMessage, vm.files.isEmpty {
            ModuleErrorView(message: error) {
                Task { await vm.load(announce: true) }
            }
            .accessibilityFocused($focusContent)
        } else if vm.files.isEmpty {
            // The common case on an idle NAS, not an anomaly: the text says so, so that an
            // empty screen is not taken for a load that failed.
            EmptyModuleView(
                title: "opened_files.empty.title",
                systemImage: "doc",
                description: "opened_files.empty.description"
            )
            .accessibilityFocused($focusContent)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let error = vm.errorMessage {
                    Text(error)
                        .foregroundStyle(.readableRed)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                Text("common.label.open_files")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .accessibilityFocused($focusContent)

                Table(vm.files.sorted(using: order), sortOrder: $order) {
                    TableColumn("common.value.file", value: \.sortableName) { file in
                        Text(file.displayName)
                    }
                    // The folder alone, without repeating the file name: DSM puts both in
                    // `path`, which ends with the name.
                    TableColumn("common.value.folder", value: \.sortableFolder) { file in
                        Text(vm.folderText(for: file))
                    }
                    TableColumn("common.column.service", value: \.sortableService) { file in
                        Text(vm.serviceText(for: file))
                    }
                    TableColumn("common.column.account", value: \.sortableAccount) { file in
                        Text(vm.accountText(for: file))
                    }
                    TableColumn("opened_files.column.host", value: \.sortableHost) { file in
                        Text(vm.hostText(for: file))
                    }
                }
                .accessibilityLabel("common.label.open_files")

                Text("opened_files.columns.dash.description")
                    .font(.callout)
                    .foregroundStyle(.readableSecondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                if vm.isTruncated {
                    Text(String(localized: "opened_files.filtered_count.description", defaultValue: "\(vm.files.count) of \(vm.totalCount) open files shown."))
                        .font(.callout)
                        .foregroundStyle(.readableSecondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            }
        }
    }
}
