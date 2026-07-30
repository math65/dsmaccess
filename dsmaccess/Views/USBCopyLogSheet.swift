//
//  USBCopyLogSheet.swift
//  dsmaccess
//

import SwiftUI

struct USBCopyLogSheet: View {
    let load: (USBCopyLogFilter, Int, Int) async throws -> USBCopyLogPage

    private let pageSize = 200
    @State private var entries: [USBCopyLogEntry] = []
    @State private var totalCount = 0
    @State private var keyword = ""
    @State private var logType = USBCopyLogType.all
    @State private var usesDateRange = false
    @State private var fromDate = Date.now.addingTimeInterval(-604_800)
    @State private var toDate = Date.now
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AccessibilityFocusState private var contentFocused: Bool
    @AccessibilityFocusState private var errorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text("usb_copy.log.title")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding()

            Form {
                Section("usb_copy.log.filter.action") {
                    TextField("common.field.search_log", text: $keyword)
                        .onSubmit { Task { await loadEntries() } }
                    Picker("usb_copy.log.filter.event_type.label", selection: $logType) {
                        ForEach(USBCopyLogType.allCases) { type in
                            Text(type.localizedName).tag(type)
                        }
                    }
                    Toggle("usb_copy.log.filter.date_range.label", isOn: $usesDateRange)
                    if usesDateRange {
                        DatePicker("usb_copy.log.filter.from.label", selection: $fromDate, displayedComponents: .date)
                        DatePicker("usb_copy.log.filter.to.label", selection: $toDate, displayedComponents: .date)
                    }
                    Button("usb_copy.log.filter.apply.action", systemImage: "line.3.horizontal.decrease.circle") {
                        Task { await loadEntries() }
                    }
                    .disabled(isLoading || (usesDateRange && fromDate > toDate))
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 230)

            Divider()
            if isLoading && entries.isEmpty {
                ModuleLoadingView("usb_copy.log.loading")
                    .accessibilityFocused($contentFocused)
            } else if let errorMessage, entries.isEmpty {
                ModuleErrorView(message: errorMessage) { Task { await loadEntries() } }
                    .accessibilityFocused($errorFocused)
            } else if entries.isEmpty {
                EmptyModuleView(
                    title: "usb_copy.log.empty",
                    systemImage: "doc.text.magnifyingglass",
                    description: "usb_copy.log.empty.description"
                )
                .accessibilityFocused($contentFocused)
            } else {
                List {
                    ForEach(entries.indices, id: \.self) { index in
                        USBCopyLogRow(entry: entries[index])
                    }
                    if entries.count < totalCount {
                        Button("usb_copy.log.load_more.action") {
                            Task { await loadEntries(reset: false) }
                        }
                        .disabled(isLoading)
                    }
                }
                .accessibilityLabel("usb_copy.log.events.label")
                .accessibilityFocused($contentFocused)
            }

            Divider()
            HStack {
                Text(String(localized: "common.status.entries_shown", defaultValue: "\(entries.count) entries shown out of \(totalCount)"))
                    .foregroundStyle(.readableSecondary)
                if isLoading && !entries.isEmpty {
                    ProgressView("usb_copy.log.loading")
                        .controlSize(.small)
                }
                if let errorMessage, !entries.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.readableRed)
                        .accessibilityFocused($errorFocused)
                }
                Spacer()
                Button("common.button.close", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 760, minHeight: 680)
        .task {
            await loadEntries()
            guard !Task.isCancelled else { return }
            contentFocused = true
        }
    }

    private var filter: USBCopyLogFilter {
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: toDate))?
            .addingTimeInterval(-1)
        return USBCopyLogFilter(
            descriptionIDs: USBCopyLogFilter.all.descriptionIDs,
            keyword: trimmedKeyword.isEmpty ? nil : trimmedKeyword,
            fromTimestamp: usesDateRange ? Int(calendar.startOfDay(for: fromDate).timeIntervalSince1970) : nil,
            toTimestamp: usesDateRange ? endOfDay.map { Int($0.timeIntervalSince1970) } : nil,
            logType: logType.rawValue
        )
    }

    private func loadEntries(reset: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        if reset {
            entries = []
            totalCount = 0
        }
        defer { isLoading = false }
        VoiceOver.announce(String(localized: "usb_copy.log.loading"), category: .progress)
        do {
            let offset = reset ? 0 : entries.count
            let page = try await load(filter, offset, pageSize)
            guard !Task.isCancelled else { return }
            if reset {
                entries = page.logList
            } else {
                entries.append(contentsOf: page.logList)
            }
            totalCount = page.count
            VoiceOver.announce(
                String(localized: "usb_copy.log.loaded.announcement", defaultValue: "\(page.logList.count) log entries loaded"),
                category: .result
            )
        } catch {
            guard !DSMError.isCancellation(error) else { return }
            errorMessage = (error as? DSMError)?.errorDescription ?? error.localizedDescription
            errorFocused = true
            VoiceOver.announce(errorMessage ?? "", category: .error, priority: .high)
        }
    }
}

private struct USBCopyLogRow: View {
    let entry: USBCopyLogEntry

    var body: some View {
        VStack(alignment: .leading) {
            Text(descriptionText)
            HStack {
                Text(logTypeName)
                Text(Date(timeIntervalSince1970: TimeInterval(entry.timestamp)), format: .dateTime)
                if let taskID = entry.taskID {
                    Text(String(localized: "usb_copy.log.task.fallback_name", defaultValue: "Task \(taskID)"))
                }
                if let error = errorText {
                    Text(error)
                        .foregroundStyle(.readableRed)
                }
            }
            .font(.caption)
            .foregroundStyle(.readableSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var logTypeName: String {
        USBCopyLogType(rawValue: entry.logType)?.localizedName ?? String(localized: "common.value.not_available")
    }

    private var descriptionText: String {
        let parameter = decodedParameter
        return switch entry.descriptionID {
        case 0: String(localized: "usb_copy.log.event.task_created", defaultValue: "Task created: \(parameter)")
        case 1: String(localized: "common.status.task_deleted", defaultValue: "Task deleted: \(parameter)")
        case 2: String(localized: "common.status.task_enabled", defaultValue: "Task enabled: \(parameter)")
        case 3: String(localized: "common.status.task_disabled", defaultValue: "Task disabled: \(parameter)")
        case 10: String(localized: "usb_copy.log.event.task_renamed", defaultValue: "Task name changed: \(parameter)")
        case 11: String(localized: "usb_copy.log.event.task_settings_changed", defaultValue: "Task settings changed: \(parameter)")
        case 100: String(localized: "common.status.task_started", defaultValue: "Task started: \(parameter)")
        case 101: String(localized: "usb_copy.log.event.task_completed", defaultValue: "Task completed: \(parameter)")
        case 102: String(localized: "usb_copy.log.event.task_cancelled", defaultValue: "Task cancelled: \(parameter)")
        case 103: String(localized: "usb_copy.log.event.task_failed", defaultValue: "Task failed: \(parameter)")
        case 104: String(localized: "usb_copy.log.event.version_rotation", defaultValue: "Version rotation: \(parameter)")
        case 105: String(localized: "usb_copy.log.event.task_completed_with_errors", defaultValue: "Task completed with errors: \(parameter)")
        case 1000: String(localized: "usb_copy.log.event.file_error", defaultValue: "File error: \(parameter)")
        default: String(localized: "usb_copy.log.event.row.label", defaultValue: "USB Copy event \(entry.descriptionID): \(parameter)")
        }
    }

    private var decodedParameter: String {
        guard let raw = entry.descriptionParameter, !raw.isEmpty else {
            return String(localized: "usb_copy.log.reason.no_details")
        }
        guard let data = raw.data(using: .utf8) else { return raw }
        if let value = try? JSONDecoder().decode(String.self, from: data) { return value }
        if let values = try? JSONDecoder().decode([String].self, from: data) {
            return values.formatted(.list(type: .and))
        }
        return raw
    }

    private var errorText: String? {
        guard let raw = entry.error, !raw.isEmpty else { return nil }
        guard let code = Int(raw) else { return raw }
        guard code != 0 else { return nil }
        return switch code {
        case -1: String(localized: "usb_copy.log.reason.cancellation")
        case -4: String(localized: "usb_copy.log.reason.invalid_parameter")
        case -9: String(localized: "common.error.permission_denied")
        case -10: String(localized: "usb_copy.log.reason.file_error")
        case -11: String(localized: "usb_copy.log.reason.file_too_large")
        case -12: String(localized: "usb_copy.log.reason.unsupported_file_name")
        case -13: String(localized: "usb_copy.log.reason.folder_unmounted")
        case -14: String(localized: "usb_copy.log.reason.resume_failed")
        case -15: String(localized: "usb_copy.log.reason.source_file_missing")
        case -16: String(localized: "usb_copy.log.reason.destination_file_exists")
        case -17: String(localized: "usb_copy.log.reason.destination_conflict")
        case -18: String(localized: "usb_copy.log.reason.incompatible_destination_type")
        case -19: String(localized: "usb_copy.log.reason.destination_full")
        case -20: String(localized: "usb_copy.log.reason.destination_root_missing")
        case -21: String(localized: "usb_copy.log.reason.destination_parent_missing")
        case -22: String(localized: "usb_copy.log.reason.source_root_missing")
        case -24: String(localized: "usb_copy.log.reason.version_folder_conflict")
        default: String(localized: "usb_copy.log.reason.error_code", defaultValue: "error code \(code)")
        }
    }
}
