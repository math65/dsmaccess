//
//  FileInfoSheet.swift
//  dsmaccess
//
//  File Station inspector fed by refreshed DSM metadata.
//

import AppKit
import SwiftUI

struct FileInfoSheet: View {
    @Bindable var vm: FileBrowserViewModel
    let selectedItem: FileStationItem

    @Environment(\.dismiss) private var dismiss
    @State private var calculationTask: Task<Void, Never>?
    @AccessibilityFocusState private var focusTitle: Bool
    @AccessibilityFocusState private var focusError: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            HStack {
                Spacer()
                Button("common.button.close", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .help("common.button.close_information")
            }
            .padding()
        }
        .frame(width: 600, height: 650)
        .task { await load() }
        .onDisappear {
            calculationTask?.cancel()
            vm.clearInspector()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isdir ? "folder" : "doc")
                .foregroundStyle(item.isdir ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            Text(item.name)
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusTitle)
            Spacer()
            if vm.isLoadingInspectorDetails {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("files.info.loading")
            }
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingInspector && vm.inspectorItem == nil {
            ModuleLoadingView("common.status.loading_information")
        } else if let error = vm.inspectorError {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundStyle(.readableRed)
                    .multilineTextAlignment(.center)
                    .accessibilityFocused($focusError)
                Button("common.button.retry") { Task { await load() } }
                    .help("files.info.reload.button")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                if let thumbnailImage {
                    Section("files.info.preview.section") {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 420, maxHeight: 220)
                            .accessibilityLabel(String(localized: "files.info.preview.label", defaultValue: "Preview of \(item.name)"))
                    }
                }

                Section("files.info.general.section") {
                    LabeledContent("common.column.name", value: item.name)
                    LabeledContent("common.column.kind", value: item.kindDescription)
                    if let size = item.additional?.size, !item.isdir {
                        LabeledContent("common.column.size") {
                            Text(size, format: .byteCount(style: .file, includesActualByteCount: true))
                        }
                    }
                    LabeledContent("common.column.location", value: item.path)
                    if let realPath = item.additional?.realPath, realPath != item.path {
                        LabeledContent("files.info.real_path", value: realPath)
                    }
                    if let mountPointType = item.additional?.mountPointType {
                        LabeledContent("files.info.mount_type", value: mountPointType)
                    }
                }

                if item.isdir, vm.supports(.directorySize) {
                    Section("files.info.folder_contents.section") {
                        if let directorySize = vm.inspectorDirectorySize {
                            LabeledContent("files.info.total_size") {
                                Text(
                                    directorySize.totalSize,
                                    format: .byteCount(style: .file, includesActualByteCount: true)
                                )
                            }
                            LabeledContent("common.module.files") {
                                Text(directorySize.fileCount, format: .number)
                            }
                            LabeledContent("files.info.subfolders") {
                                Text(directorySize.directoryCount, format: .number)
                            }
                        } else {
                            Button("files.info.folder_size.button") {
                                calculationTask = Task {
                                    await vm.calculateInspectorDirectorySize()
                                    announceDirectorySizeResult()
                                    calculationTask = nil
                                }
                            }
                            .disabled(vm.isCalculatingInspectorSize)
                            .help("files.info.folder_size.button.hint")
                        }
                        if vm.isCalculatingInspectorSize {
                            ProgressView("files.info.folder_size.loading")
                        }
                    }
                }

                if !item.isdir, vm.supports(.checksum) {
                    Section("files.info.integrity.section") {
                        if let checksum = vm.inspectorChecksum {
                            LabeledContent("files.info.md5") {
                                HStack {
                                    Text(checksum)
                                        .font(.body.monospaced())
                                        .textSelection(.enabled)
                                    Button("common.button.copy") { copyToClipboard(checksum) }
                                        .help("files.info.md5.copy.button")
                                }
                            }
                        } else {
                            Button("files.info.md5.button") {
                                calculationTask = Task {
                                    await vm.calculateInspectorChecksum()
                                    announceChecksumResult()
                                    calculationTask = nil
                                }
                            }
                            .disabled(vm.isCalculatingInspectorChecksum)
                            .help("files.info.md5.button.hint")
                        }
                        if vm.isCalculatingInspectorChecksum {
                            ProgressView("files.info.md5.loading")
                        }
                    }
                }

                if let time = item.additional?.time {
                    Section("files.info.dates.section") {
                        dateRow("files.info.modified", timestamp: time.mtime)
                        dateRow("common.label.creation", timestamp: time.crtime ?? time.ctime)
                        dateRow("files.info.last_accessed", timestamp: time.atime)
                        dateRow("files.info.metadata_changed", timestamp: time.ctime)
                    }
                }

                if let owner = item.additional?.owner,
                   owner.user != nil || owner.group != nil || owner.uid != nil || owner.gid != nil {
                    Section("common.column.owner") {
                        if let user = owner.user { LabeledContent("common.column.user", value: user) }
                        if let uid = owner.uid {
                            LabeledContent("files.info.uid") { Text(uid, format: .number.grouping(.never)) }
                        }
                        if let group = owner.group { LabeledContent("common.column.group", value: group) }
                        if let gid = owner.gid {
                            LabeledContent("files.info.gid") { Text(gid, format: .number.grouping(.never)) }
                        }
                    }
                }

                if let permission = item.additional?.permission {
                    Section("files.info.permissions.section") {
                        if let posix = permission.posix {
                            LabeledContent("files.info.posix_mode") {
                                Text(posix, format: .number.grouping(.never))
                            }
                        }
                        if let shareRight = permission.shareRight {
                            LabeledContent("files.info.shared_folder_permission", value: shareRight)
                        }
                        if let accessList = accessList(for: permission.acl) {
                            LabeledContent("files.info.access.section", value: accessList)
                        }
                        if let restrictions = restrictions(for: permission.advancedRight) {
                            LabeledContent("files.info.restrictions.section", value: restrictions)
                        }
                        if let aclEnabled = permission.aclEnabled ?? permission.isACLMode {
                            LabeledContent("files.info.acl") {
                                Text(aclEnabled ? "common.status.enabled.feminine" : "common.status.disabled.feminine")
                            }
                        }
                    }
                }

                if let volume = item.additional?.volumeStatus {
                    Section("common.column.volume") {
                        if let freeSpace = volume.freeSpace {
                            LabeledContent("files.info.available_space") {
                                Text(freeSpace, format: .byteCount(style: .file))
                            }
                        }
                        if let totalSpace = volume.totalSpace {
                            LabeledContent("common.column.capacity") {
                                Text(totalSpace, format: .byteCount(style: .file))
                            }
                        }
                        if let isReadOnly = volume.isReadOnly {
                            LabeledContent("files.info.volume_access") {
                                Text(isReadOnly ? "common.permission.read_only" : "files.info.permission.read_write")
                            }
                        }
                    }
                }

                if !vm.inspectorDetailErrors.isEmpty {
                    Section("files.info.partial.title") {
                        ForEach(vm.inspectorDetailErrors, id: \.self) { error in
                            Text(error)
                                .foregroundStyle(.readableRed)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityLabel(String(localized: "common.title.information_for", defaultValue: "Information for \(item.name)"))
        }
    }

    private var item: FileStationItem { vm.inspectorItem ?? selectedItem }

    private var thumbnailImage: NSImage? {
        vm.inspectorThumbnail.flatMap(NSImage.init(data:))
    }

    @ViewBuilder
    private func dateRow(_ label: LocalizedStringKey, timestamp: Int?) -> some View {
        if let timestamp {
            LabeledContent(label) {
                Text(
                    Date(timeIntervalSince1970: TimeInterval(timestamp)),
                    format: Date.FormatStyle(date: .long, time: .standard)
                )
            }
        }
    }

    private func accessList(for acl: FileStationItem.ACLInfo?) -> String? {
        guard let acl else { return nil }
        var access = [String]()
        if acl.read == true { access.append(String(localized: "common.metric.read")) }
        if acl.write == true { access.append(String(localized: "common.metric.write")) }
        if acl.append == true { access.append(String(localized: "files.info.permission.append")) }
        if acl.execute == true { access.append(String(localized: "files.info.permission.execute")) }
        if acl.delete == true { access.append(String(localized: "common.operation.deletion")) }
        return access.isEmpty ? String(localized: "common.value.none") : access.formatted(.list(type: .and))
    }

    private func restrictions(for rights: FileStationItem.AdvancedRight?) -> String? {
        guard let rights else { return nil }
        var restrictions = [String]()
        if rights.disablesDownload == true {
            restrictions.append(String(localized: "files.info.restriction.download_denied"))
        }
        if rights.disablesList == true {
            restrictions.append(String(localized: "files.info.restriction.listing_denied"))
        }
        if rights.disablesModify == true {
            restrictions.append(String(localized: "files.info.restriction.write_denied"))
        }
        return restrictions.isEmpty ? nil : restrictions.formatted(.list(type: .and))
    }

    private func load() async {
        focusTitle = true
        VoiceOver.announce(
            String(localized: "files.info.loading.named", defaultValue: "Loading information about \(selectedItem.name)…"),
            category: .progress,
            priority: .low
        )
        await vm.loadInspector(for: selectedItem)
        guard !Task.isCancelled else { return }
        if let error = vm.inspectorError {
            focusError = true
            VoiceOver.announce(error, category: .error, priority: .high)
        } else {
            focusTitle = true
            VoiceOver.announce(
                String(localized: "files.info.reloaded", defaultValue: "Information about \(selectedItem.name) updated"),
                category: .result
            )
            if !vm.inspectorDetailErrors.isEmpty {
                VoiceOver.announce(
                    String(localized: "files.info.partial.description"),
                    category: .error
                )
            }
        }
    }

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        VoiceOver.announce(String(localized: "files.info.md5.copied"), category: .result)
    }

    private func announceDirectorySizeResult() {
        if let size = vm.inspectorDirectorySize {
            VoiceOver.announce(
                String(
                    localized: "files.info.folder_size.done",
                    defaultValue: "Folder size calculated: \(size.totalSize.formatted(.byteCount(style: .file)))"
                ),
                category: .result
            )
        } else if let error = vm.inspectorDetailErrors.last {
            VoiceOver.announce(error, category: .error, priority: .high)
        }
    }

    private func announceChecksumResult() {
        if vm.inspectorChecksum != nil {
            VoiceOver.announce(String(localized: "files.info.md5.done"), category: .result)
        } else if let error = vm.inspectorDetailErrors.last {
            VoiceOver.announce(error, category: .error, priority: .high)
        }
    }
}
