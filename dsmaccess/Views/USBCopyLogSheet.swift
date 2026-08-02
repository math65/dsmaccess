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
    @State private var order = [KeyPathComparator(\USBCopyLogEntry.timestamp, order: .reverse)]
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
            .accessibilityLabel("usb_copy.log.filter.label")
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
                Table(entries.sorted(using: order), sortOrder: $order) {
                    TableColumn("common.column.date", value: \.timestamp) { entry in
                        Text(entry.date, format: .dateTime)
                    }
                    TableColumn("common.column.kind", value: \.sortableLogType) { entry in
                        Text(entry.logTypeName)
                    }
                    TableColumn("usb_copy.log.column.task", value: \.sortableTask) { entry in
                        Text(entry.taskDescription)
                    }
                    TableColumn("usb_copy.log.column.event", value: \.sortableEvent) { entry in
                        Text(entry.eventDescription)
                    }
                    TableColumn("common.column.message", value: \.sortableError) { entry in
                        Text(entry.errorText ?? "—")
                            .foregroundStyle(
                                entry.errorText == nil ? .readableSecondary : .readableRed
                            )
                    }
                }
                .accessibilityLabel("usb_copy.log.events.label")
                .accessibilityFocused($contentFocused)

                if entries.count < totalCount {
                    Button("usb_copy.log.load_more.action") {
                        Task { await loadEntries(reset: false) }
                    }
                    .disabled(isLoading)
                    .padding(.vertical, 8)
                }
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
