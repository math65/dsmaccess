//
//  HyperBackupEntryTableView.swift
//  dsmaccess
//
//  Native table for browsing what a backup version holds, with the Finder-style
//  selection, keyboard handling and contextual actions of the File Station browser.
//

@preconcurrency import AppKit
import SwiftUI

struct HyperBackupEntryTableView: NSViewRepresentable {
    var entries: [HyperBackupEntry]
    @Binding var selection: Set<String>
    @Binding var sortMode: HyperBackupRestoreViewModel.SortMode
    @Binding var sortAscending: Bool
    var focusRequestID: Int
    var isRestoring: Bool
    var isDownloading: Bool
    var isAtRoot: Bool
    var onOpen: (HyperBackupEntry) -> Void
    var onRestoreCopy: ([HyperBackupEntry]) -> Void
    var onRestoreInPlace: ([HyperBackupEntry]) -> Void
    var onDownload: (HyperBackupEntry) -> Void
    var onGoUp: () -> Void
    var onGoToRoot: () -> Void

    /// Displayed order. The kind comes right after the name so that a row read in one go says
    /// "documents, folder" before its measurements. The condition closes the row: it is empty
    /// on everything DSM reports as healthy.
    private static let sortableColumns: [HyperBackupRestoreViewModel.SortMode] = [
        .name, .size, .modificationDate,
    ]

    private static let kindColumnIdentifier = NSUserInterfaceItemIdentifier("kind")
    private static let conditionColumnIdentifier = NSUserInterfaceItemIdentifier("condition")

    /// The kind and the condition carry no sort: a folder always precedes a file whatever the
    /// axis, and DSM reports a condition on a handful of rows at most.
    private static func makeColumns() -> [NSTableColumn] {
        var columns = [NSTableColumn]()
        for mode in sortableColumns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(mode.rawValue))
            column.title = mode.title
            column.sortDescriptorPrototype = NSSortDescriptor(key: mode.rawValue, ascending: true)
            switch mode {
            case .name:
                column.width = 280
                column.minWidth = 150
                column.resizingMask = [.userResizingMask, .autoresizingMask]
            case .size:
                column.width = 100
                column.minWidth = 70
                column.headerCell.alignment = .right
            case .modificationDate:
                column.width = 180
                column.minWidth = 120
            }
            columns.append(column)
        }

        let kind = NSTableColumn(identifier: kindColumnIdentifier)
        kind.title = String(localized: "common.column.kind")
        kind.width = 120
        kind.minWidth = 80
        columns.insert(kind, at: 1)

        let condition = NSTableColumn(identifier: conditionColumnIdentifier)
        condition.title = String(localized: "common.column.state")
        condition.width = 200
        condition.minWidth = 100
        columns.append(condition)
        return columns
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyboardTableView()
        table.headerView = NSTableHeaderView()
        table.rowHeight = 28
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.style = .inset
        table.setAccessibilityLabel(String(localized: "hyper_backup.restore.table.label"))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        for column in Self.makeColumns() {
            table.addTableColumn(column)
        }
        context.coordinator.applySortDescriptor(to: table, mode: sortMode, ascending: sortAscending)

        table.onActivate = { [weak coordinator = context.coordinator] in coordinator?.activateSelection() }
        table.onGoUp = { [weak coordinator = context.coordinator] in coordinator?.parent.onGoUp() }
        table.onDownload = { [weak coordinator = context.coordinator] in coordinator?.downloadSelection() }
        table.menuProvider = { [weak coordinator = context.coordinator] event in
            coordinator?.contextMenu(for: event)
        }

        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.tableDoubleClicked(_:))
        context.coordinator.tableView = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = nsView.documentView as? KeyboardTableView else { return }

        context.coordinator.isApplyingSelection = true
        let currentRows = entries.map {
            let size = $0.size.map(String.init) ?? ""
            let modified = $0.modificationTimestamp.map(String.init) ?? ""
            return "\(isRestoring)|\(isDownloading)|\($0.isFolder)|\($0.path)|\($0.name)"
                + "|\(size)|\(modified)|\($0.warningDescription ?? "")"
        }
        if context.coordinator.rowPresentationKeys != currentRows {
            table.reloadData()
            context.coordinator.rowPresentationKeys = currentRows
        }
        let selectedRows = IndexSet(entries.indices.filter { selection.contains(entries[$0].path) })
        table.selectRowIndexes(selectedRows, byExtendingSelection: false)
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            if let row = selectedRows.first,
               let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) {
                table.window?.makeFirstResponder(table)
                NSAccessibility.post(element: cell, notification: .focusedUIElementChanged)
            } else if entries.isEmpty {
                // An empty backup folder offers no row to focus, yet the table must still be
                // first responder: it is what carries ⌘↑ back out of the folder. Deferred,
                // because claiming it during this update is undone by the empty-state overlay
                // appearing right after. No accessibility notification: the VoiceOver cursor
                // belongs on the message.
                Task { [weak table] in
                    guard let table, table.window != nil else { return }
                    table.window?.makeFirstResponder(table)
                }
            }
        }
        context.coordinator.isApplyingSelection = false
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: HyperBackupEntryTableView
        weak var tableView: NSTableView?
        var isApplyingSelection = false
        var isApplyingSortDescriptor = false
        var rowPresentationKeys = [String]()
        var lastFocusRequestID = 0

        init(_ parent: HyperBackupEntryTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.entries.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.entries.indices.contains(row), let tableColumn else { return nil }
            let entry = parent.entries[row]
            switch tableColumn.identifier {
            case NSUserInterfaceItemIdentifier(HyperBackupRestoreViewModel.SortMode.name.rawValue):
                let identifier = NSUserInterfaceItemIdentifier("HyperBackupNameCell")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? HyperBackupNameCellView)
                    ?? HyperBackupNameCellView(identifier: identifier)
                cell.configure(with: entry)
                configureActions(on: cell, for: entry)
                return cell
            case NSUserInterfaceItemIdentifier(HyperBackupRestoreViewModel.SortMode.size.rawValue):
                return valueCell(in: tableView, for: entry, value: entry.sizeDescription, alignment: .right)
            case NSUserInterfaceItemIdentifier(HyperBackupRestoreViewModel.SortMode.modificationDate.rawValue):
                return valueCell(in: tableView, for: entry, value: entry.modificationDescription)
            case HyperBackupEntryTableView.kindColumnIdentifier:
                return valueCell(in: tableView, for: entry, value: entry.kindDescription)
            case HyperBackupEntryTableView.conditionColumnIdentifier:
                return valueCell(in: tableView, for: entry, value: entry.warningDescription)
            default:
                return nil
            }
        }

        private func valueCell(
            in tableView: NSTableView,
            for entry: HyperBackupEntry,
            value: String?,
            alignment: NSTextAlignment = .natural
        ) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier("HyperBackupValueCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? HyperBackupValueCellView)
                ?? HyperBackupValueCellView(identifier: identifier)
            cell.configure(value: value, alignment: alignment)
            configureActions(on: cell, for: entry)
            return cell
        }

        /// Every cell of a row carries the row's actions: the VoiceOver cursor stops on the
        /// column it was reading, and finding no action there would make them look gone.
        private func configureActions(on cell: HyperBackupRowCellView, for entry: HyperBackupEntry) {
            cell.canRestore = !parent.isRestoring
            cell.canDownload = !entry.isFolder && !entry.isDamaged && !parent.isDownloading
            cell.onPress = { [weak self] in self?.activate(entry) }
            cell.onOpen = entry.isFolder ? { [weak self] in self?.parent.onOpen(entry) } : nil
            cell.onRestoreCopy = { [weak self] in self?.parent.onRestoreCopy([entry]) }
            cell.onRestoreInPlace = { [weak self] in self?.parent.onRestoreInPlace([entry]) }
            cell.onDownload = { [weak self] in self?.parent.onDownload(entry) }
        }

        /// Written on the table only when it differs, and behind a flag: AppKit answers a
        /// programmatic assignment with the same delegate callback a header click sends, which
        /// would write the sort state back while SwiftUI is drawing it.
        func applySortDescriptor(
            to table: NSTableView,
            mode: HyperBackupRestoreViewModel.SortMode,
            ascending: Bool
        ) {
            let current = table.sortDescriptors.first
            guard current?.key != mode.rawValue || current?.ascending != ascending else { return }
            isApplyingSortDescriptor = true
            table.sortDescriptors = [NSSortDescriptor(key: mode.rawValue, ascending: ascending)]
            isApplyingSortDescriptor = false
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isApplyingSortDescriptor,
                  let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  let mode = HyperBackupRestoreViewModel.SortMode(rawValue: key) else { return }
            if parent.sortMode != mode { parent.sortMode = mode }
            if parent.sortAscending != descriptor.ascending { parent.sortAscending = descriptor.ascending }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection else { return }
            parent.selection = Set(selectedEntries.map(\.path))
        }

        var selectedEntries: [HyperBackupEntry] {
            guard let tableView else { return [] }
            return tableView.selectedRowIndexes.compactMap { row in
                parent.entries.indices.contains(row) ? parent.entries[row] : nil
            }
        }

        /// Same double-click behavior as DSM's own explorer: a folder opens, a file
        /// downloads — unless DSM marks it damaged, in which case there is nothing sane
        /// to hand over.
        private func activate(_ entry: HyperBackupEntry) {
            if entry.isFolder {
                parent.onOpen(entry)
            } else if !entry.isDamaged, !parent.isDownloading {
                parent.onDownload(entry)
            }
        }

        func activateSelection() {
            guard selectedEntries.count == 1, let entry = selectedEntries.first else { return }
            activate(entry)
        }

        func downloadSelection() {
            guard let entry = selectedEntries.first, selectedEntries.count == 1,
                  !entry.isFolder, !entry.isDamaged, !parent.isDownloading else { return }
            parent.onDownload(entry)
        }

        func contextMenu(for event: NSEvent) -> NSMenu? {
            guard let tableView else { return nil }
            let point = tableView.convert(event.locationInWindow, from: nil)
            let row = tableView.row(at: point)
            guard row >= 0 else { return nil }

            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            let entries = selectedEntries
            guard !entries.isEmpty else { return nil }

            let singleFolder = entries.count == 1 && entries[0].isFolder ? entries[0] : nil
            let downloadable = entries.count == 1 && !entries[0].isFolder && !entries[0].isDamaged
                ? entries[0] : nil
            return makeEntryContextMenu(
                canOpen: singleFolder != nil,
                canRestore: parent.canRestoreSelection(entries),
                canDownload: downloadable != nil && !parent.isDownloading,
                canGoUp: !parent.isAtRoot,
                open: { [weak self] in
                    guard let entry = self?.selectedEntries.first, entry.isFolder else { return }
                    self?.parent.onOpen(entry)
                },
                restoreCopy: { [weak self] in
                    guard let self, !self.selectedEntries.isEmpty else { return }
                    self.parent.onRestoreCopy(self.selectedEntries)
                },
                restoreInPlace: { [weak self] in
                    guard let self, !self.selectedEntries.isEmpty else { return }
                    self.parent.onRestoreInPlace(self.selectedEntries)
                },
                download: { [weak self] in self?.downloadSelection() },
                goUp: { [weak self] in self?.parent.onGoUp() },
                goToRoot: { [weak self] in self?.parent.onGoToRoot() }
            )
        }

        @objc func tableDoubleClicked(_ sender: NSTableView) {
            guard sender.clickedRow >= 0, parent.entries.indices.contains(sender.clickedRow) else { return }
            activate(parent.entries[sender.clickedRow])
        }
    }

    fileprivate func canRestoreSelection(_ entries: [HyperBackupEntry]) -> Bool {
        !entries.isEmpty && !isRestoring
    }
}

private final class ClosureMenuTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() { handler() }
}

private func closureMenuItem(title: String, enabled: Bool, handler: @escaping () -> Void) -> NSMenuItem {
    let target = ClosureMenuTarget(handler: handler)
    let item = NSMenuItem(title: title, action: #selector(ClosureMenuTarget.fire), keyEquivalent: "")
    item.target = target
    item.isEnabled = enabled
    item.toolTip = title
    // `target` is weak on NSMenuItem; representedObject keeps it alive for the menu's lifetime.
    item.representedObject = target
    return item
}

/// The same entries in the same order whatever the selection holds, so the menu never
/// changes shape from one row to the next; what does not apply is listed disabled.
private func makeEntryContextMenu(
    canOpen: Bool,
    canRestore: Bool,
    canDownload: Bool,
    canGoUp: Bool,
    open: @escaping () -> Void,
    restoreCopy: @escaping () -> Void,
    restoreInPlace: @escaping () -> Void,
    download: @escaping () -> Void,
    goUp: @escaping () -> Void,
    goToRoot: @escaping () -> Void
) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(closureMenuItem(
        title: String(localized: "hyper_backup.restore.open.button"),
        enabled: canOpen,
        handler: open
    ))
    menu.addItem(closureMenuItem(
        title: String(localized: "hyper_backup.restore.copy_to.button"),
        enabled: canRestore,
        handler: restoreCopy
    ))
    menu.addItem(closureMenuItem(
        title: String(localized: "hyper_backup.restore.in_place.button"),
        enabled: canRestore,
        handler: restoreInPlace
    ))
    menu.addItem(closureMenuItem(
        title: String(localized: "hyper_backup.restore.download.button"),
        enabled: canDownload,
        handler: download
    ))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(closureMenuItem(
        title: String(localized: "hyper_backup.restore.go_up.button"),
        enabled: canGoUp,
        handler: goUp
    ))
    menu.addItem(closureMenuItem(
        title: String(localized: "hyper_backup.restore.go_to_root.button"),
        enabled: canGoUp,
        handler: goToRoot
    ))
    return menu
}

/// Shared base for the cells of a backup entry. Each column is its own accessibility element,
/// so the row's actions have to travel with every cell.
class HyperBackupRowCellView: NSTableCellView {
    /// Same double-click gesture as the table: a folder opens, a file downloads.
    var onPress: (() -> Void)?
    /// Nil for a file, so the menu's "Open" stays disabled instead of downloading.
    var onOpen: (() -> Void)?
    var onRestoreCopy: (() -> Void)?
    var onRestoreInPlace: (() -> Void)?
    var onDownload: (() -> Void)?
    var canRestore = false
    var canDownload = false

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = [NSAccessibilityCustomAction]()
        if canRestore {
            appendAction(named: String(localized: "hyper_backup.restore.copy_to.button"), handler: onRestoreCopy, to: &actions)
            appendAction(named: String(localized: "hyper_backup.restore.in_place.button"), handler: onRestoreInPlace, to: &actions)
        }
        if canDownload {
            appendAction(named: String(localized: "hyper_backup.restore.download.button"), handler: onDownload, to: &actions)
        }
        return actions.isEmpty ? nil : actions
    }

    override func accessibilityPerformShowMenu() -> Bool {
        let menu = makeEntryContextMenu(
            canOpen: onOpen != nil,
            canRestore: canRestore,
            canDownload: canDownload,
            canGoUp: false,
            open: { [weak self] in self?.onOpen?() },
            restoreCopy: { [weak self] in self?.onRestoreCopy?() },
            restoreInPlace: { [weak self] in self?.onRestoreInPlace?() },
            download: { [weak self] in self?.onDownload?() },
            goUp: { },
            goToRoot: { }
        )
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.maxY), in: self)
        return true
    }

    private func appendAction(
        named name: String,
        handler: (() -> Void)?,
        to actions: inout [NSAccessibilityCustomAction]
    ) {
        guard let handler else { return }
        actions.append(NSAccessibilityCustomAction(name: name) {
            handler()
            return true
        })
    }
}

final class HyperBackupNameCellView: HyperBackupRowCellView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }

    private func setup() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.lineBreakMode = .byTruncatingTail
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The icon only doubles the kind and condition columns; announcing it would repeat them.
        iconView.setAccessibilityElement(false)

        addSubview(iconView)
        addSubview(nameField)
        imageView = iconView
        textField = nameField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with entry: HyperBackupEntry) {
        // The warning word is written in the condition column; the icon only doubles it.
        let warns = entry.warningDescription != nil
        iconView.image = NSImage(
            systemSymbolName: warns ? "exclamationmark.triangle" : (entry.isFolder ? "folder" : "doc"),
            accessibilityDescription: nil
        )
        iconView.contentTintColor = warns
            ? .systemOrange
            : (entry.isFolder ? .controlAccentColor : .secondaryLabelColor)
        nameField.stringValue = entry.name
        setAccessibilityLabel(entry.name)
    }
}

final class HyperBackupValueCellView: HyperBackupRowCellView {
    private let valueField = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) non supporté") }

    private func setup() {
        valueField.translatesAutoresizingMaskIntoConstraints = false
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The cell speaks for its column; leaving the field addressable too would read the
        // value twice, and would put the placeholder back on a cell meant to stay silent.
        valueField.setAccessibilityElement(false)

        addSubview(valueField)
        textField = valueField

        NSLayoutConstraint.activate([
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// A nil value is written as the Finder's placeholder and left unspoken: a condition column
    /// empty on every healthy row would otherwise say a dash on each one.
    func configure(value: String?, alignment: NSTextAlignment) {
        valueField.stringValue = value ?? TableValueText.absentValue
        valueField.alignment = alignment
        setAccessibilityLabel(value ?? "")
    }
}
