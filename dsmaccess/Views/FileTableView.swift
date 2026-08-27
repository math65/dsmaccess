//
//  FileTableView.swift
//  dsmaccess
//
//  Native File Station table with Finder-style selection, keyboard handling and
//  contextual actions. AppKit is used here because NSTableView provides the Mac's
//  expected multi-selection and VoiceOver table semantics.
//

@preconcurrency import AppKit
import SwiftUI

struct FileActionAvailability: Equatable {
    var canDownload: Bool
    var canRename: Bool
    var canDelete: Bool
    var canCopyMove: Bool
    var canShare: Bool
    var canCompress: Bool
    var canExtract: Bool
}

struct FileTableView: NSViewRepresentable {
    var items: [FileStationItem]
    @Binding var selection: Set<String>
    @Binding var sortMode: FileBrowserViewModel.SortMode
    @Binding var sortAscending: Bool
    var focusRequestID: Int
    var actionAvailability: FileActionAvailability
    var showsPath: Bool
    var canExtract: (FileStationItem) -> Bool
    var onActivate: (FileStationItem) -> Void
    var onDownload: ([FileStationItem]) -> Void
    var onRename: (FileStationItem) -> Void
    var onDelete: ([FileStationItem]) -> Void
    var onCopy: ([FileStationItem]) -> Void
    var onShare: (FileStationItem) -> Void
    var onCompress: ([FileStationItem]) -> Void
    var onExtract: (FileStationItem) -> Void
    var onShowInfo: (FileStationItem) -> Void
    var onGoUp: () -> Void
    var onPaste: () -> Void
    var onMoveHere: () -> Void
    var makeDragProvider: (FileStationItem) -> NSFilePromiseProvider?

    /// Displayed order. The kind comes right after the name so that a row read in one go still
    /// says "photos, folder" before its measurements — the order the single-column table spoke.
    private static let sortableColumns: [FileBrowserViewModel.SortMode] = [
        .name, .kind, .size, .modificationDate,
    ]

    /// The location only carries information in search results, where two rows can come from
    /// opposite ends of the NAS; elsewhere it repeats the folder the user is already in.
    private static let pathColumnIdentifier = NSUserInterfaceItemIdentifier("path")

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyboardTableView()
        table.headerView = NSTableHeaderView()
        table.rowHeight = 28
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.style = .inset
        table.setAccessibilityLabel(String(localized: "files.table.label"))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        for mode in Self.sortableColumns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(mode.rawValue))
            column.title = mode.title
            column.sortDescriptorPrototype = NSSortDescriptor(key: mode.rawValue, ascending: true)
            switch mode {
            case .name:
                column.width = 280
                column.minWidth = 150
                column.resizingMask = [.userResizingMask, .autoresizingMask]
            case .kind:
                column.width = 150
                column.minWidth = 80
            case .size:
                column.width = 100
                column.minWidth = 70
                column.headerCell.alignment = .right
            case .modificationDate:
                column.width = 180
                column.minWidth = 120
            }
            table.addTableColumn(column)
        }

        let pathColumn = NSTableColumn(identifier: Self.pathColumnIdentifier)
        pathColumn.title = String(localized: "common.column.location")
        pathColumn.width = 240
        pathColumn.minWidth = 120
        pathColumn.isHidden = !showsPath
        table.addTableColumn(pathColumn)
        context.coordinator.applySortDescriptor(to: table, mode: sortMode, ascending: sortAscending)

        table.onActivate = { [weak coordinator = context.coordinator] in coordinator?.activateSelection() }
        table.onGoUp = { [weak coordinator = context.coordinator] in coordinator?.parent.onGoUp() }
        table.onDownload = { [weak coordinator = context.coordinator] in coordinator?.downloadSelection() }
        table.onRename = { [weak coordinator = context.coordinator] in coordinator?.renameSelection() }
        table.onDelete = { [weak coordinator = context.coordinator] in coordinator?.deleteSelection() }
        table.onCopy = { [weak coordinator = context.coordinator] in coordinator?.copySelection() }
        table.onShowInfo = { [weak coordinator = context.coordinator] in coordinator?.showInfoForSelection() }
        // Paste and move target the displayed folder, not the selection:
        // no logic in the coordinator.
        table.onPaste = { [weak coordinator = context.coordinator] in coordinator?.parent.onPaste() }
        table.onMoveHere = { [weak coordinator = context.coordinator] in coordinator?.parent.onMoveHere() }
        table.menuProvider = { [weak coordinator = context.coordinator] event in
            coordinator?.contextMenu(for: event)
        }

        // Dragging to the Finder: copy is the only direction offered outside the app.
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

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

        if let pathColumn = table.tableColumn(withIdentifier: Self.pathColumnIdentifier),
           pathColumn.isHidden == showsPath {
            pathColumn.isHidden = !showsPath
        }
        context.coordinator.applySortDescriptor(to: table, mode: sortMode, ascending: sortAscending)

        context.coordinator.isApplyingSelection = true
        // The values the cells read, not the text they show: formatting every row on every
        // update would put a byte count and a date formatter between each keystroke and the
        // screen, for rows that are mostly off-screen.
        let currentRows = items.map {
            let size = $0.additional?.size.map(String.init) ?? ""
            let modified = $0.additional?.time?.mtime.map(String.init) ?? ""
            return "\(actionAvailability)|\(showsPath)|\($0.isdir)|\($0.path)|\($0.name)|\(size)|\(modified)"
        }
        if context.coordinator.rowPresentationKeys != currentRows {
            table.reloadData()
            context.coordinator.rowPresentationKeys = currentRows
        }
        let selectedRows = IndexSet(items.indices.filter { selection.contains(items[$0].path) })
        table.selectRowIndexes(selectedRows, byExtendingSelection: false)
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            if let row = selectedRows.first,
               let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) {
                table.window?.makeFirstResponder(table)
                NSAccessibility.post(element: cell, notification: .focusedUIElementChanged)
            } else if items.isEmpty {
                // An empty folder offers no row to focus, yet the table must still be first
                // responder: it is what carries ⌘V. Deferred, because claiming it during this
                // update is undone by the empty-state overlay appearing right after. No
                // accessibility notification: the VoiceOver cursor belongs on the message.
                Task { [weak table] in
                    guard let table, table.window != nil else { return }
                    table.window?.makeFirstResponder(table)
                }
            }
        }
        context.coordinator.isApplyingSelection = false
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?
        var isApplyingSelection = false
        var isApplyingSortDescriptor = false
        var rowPresentationKeys = [String]()
        var lastFocusRequestID = 0

        init(_ parent: FileTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.items.indices.contains(row), let tableColumn else { return nil }
            let item = parent.items[row]
            switch FileBrowserViewModel.SortMode(rawValue: tableColumn.identifier.rawValue) {
            case .name:
                let identifier = NSUserInterfaceItemIdentifier("FileNameCell")
                let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? FileNameCellView)
                    ?? FileNameCellView(identifier: identifier)
                cell.configure(with: item)
                configureActions(on: cell, for: item)
                return cell
            case .kind:
                return valueCell(in: tableView, for: item, value: item.kindDescription)
            case .size:
                return valueCell(in: tableView, for: item, value: item.sizeDescription, alignment: .right)
            case .modificationDate:
                return valueCell(in: tableView, for: item, value: item.modificationDescription)
            case nil:
                // The path column: its end identifies the row, so it is the head that is cut.
                return valueCell(in: tableView, for: item, value: item.path, truncatesHead: true)
            }
        }

        private func valueCell(
            in tableView: NSTableView,
            for item: FileStationItem,
            value: String,
            alignment: NSTextAlignment = .natural,
            truncatesHead: Bool = false
        ) -> NSView {
            let identifier = NSUserInterfaceItemIdentifier("FileValueCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? FileValueCellView)
                ?? FileValueCellView(identifier: identifier)
            cell.configure(value: value, alignment: alignment, truncatesHead: truncatesHead)
            configureActions(on: cell, for: item)
            return cell
        }

        /// Every cell of a row carries the row's actions: the VoiceOver cursor stops on the
        /// column it was reading, and finding no action there would make them look gone.
        private func configureActions(on cell: FileRowCellView, for item: FileStationItem) {
            cell.actionAvailability = parent.actionAvailability
            cell.canExtractSelectedItem = parent.actionAvailability.canExtract && parent.canExtract(item)
            cell.onPress = { [weak self] in self?.parent.onActivate(item) }
            cell.onDownload = { [weak self] in self?.parent.onDownload([item]) }
            cell.onRename = { [weak self] in self?.parent.onRename(item) }
            cell.onDelete = { [weak self] in self?.parent.onDelete([item]) }
            cell.onCopy = { [weak self] in self?.parent.onCopy([item]) }
            cell.onShare = { [weak self] in self?.parent.onShare(item) }
            cell.onCompress = { [weak self] in self?.parent.onCompress([item]) }
            cell.onExtract = { [weak self] in self?.parent.onExtract(item) }
            cell.onShowInfo = { [weak self] in self?.parent.onShowInfo(item) }
        }

        /// Written on the table only when it differs, and behind a flag: AppKit answers a
        /// programmatic assignment with the same delegate callback a header click sends, which
        /// would write the sort state back while SwiftUI is drawing it.
        func applySortDescriptor(
            to table: NSTableView,
            mode: FileBrowserViewModel.SortMode,
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
                  let mode = FileBrowserViewModel.SortMode(rawValue: key) else { return }
            if parent.sortMode != mode { parent.sortMode = mode }
            if parent.sortAscending != descriptor.ascending { parent.sortAscending = descriptor.ascending }
        }

        func tableView(
            _ tableView: NSTableView,
            pasteboardWriterForRow row: Int
        ) -> (any NSPasteboardWriting)? {
            guard parent.actionAvailability.canDownload,
                  parent.items.indices.contains(row) else { return nil }
            return parent.makeDragProvider(parent.items[row])
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            FinderPasteboard.dragSessionWillBegin()
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection else { return }
            parent.selection = Set(selectedItems.map(\.path))
        }

        var selectedItems: [FileStationItem] {
            guard let tableView else { return [] }
            return tableView.selectedRowIndexes.compactMap { row in
                parent.items.indices.contains(row) ? parent.items[row] : nil
            }
        }

        func activateSelection() {
            guard selectedItems.count == 1, let item = selectedItems.first else { return }
            parent.onActivate(item)
        }

        func downloadSelection() {
            let items = selectedItems
            guard !items.isEmpty else { return }
            parent.onDownload(items)
        }

        func renameSelection() {
            guard parent.actionAvailability.canRename,
                  selectedItems.count == 1,
                  let item = selectedItems.first else { return }
            parent.onRename(item)
        }

        func deleteSelection() {
            let items = selectedItems
            guard parent.actionAvailability.canDelete, !items.isEmpty else { return }
            parent.onDelete(items)
        }

        func copySelection() {
            let items = selectedItems
            guard parent.actionAvailability.canCopyMove, !items.isEmpty else { return }
            parent.onCopy(items)
        }

        func showInfoForSelection() {
            guard selectedItems.count == 1, let item = selectedItems.first else { return }
            parent.onShowInfo(item)
        }

        func contextMenu(for event: NSEvent) -> NSMenu? {
            guard let tableView else { return nil }
            let point = tableView.convert(event.locationInWindow, from: nil)
            let row = tableView.row(at: point)
            guard row >= 0 else { return nil }

            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            let items = selectedItems
            guard !items.isEmpty else { return nil }

            return makeFileContextMenu(
                availability: parent.actionAvailability,
                canExtractSelectedItem: items.count == 1 && parent.canExtract(items[0]),
                activate: items.count == 1 ? { [weak self] in self?.activateSelection() } : nil,
                download: { [weak self] in self?.downloadSelection() },
                rename: items.count == 1 ? { [weak self] in self?.renameSelection() } : nil,
                delete: { [weak self] in self?.deleteSelection() },
                copy: { [weak self] in self?.copySelection() },
                share: items.count == 1 ? { [weak self] in
                    guard let item = self?.selectedItems.first else { return }
                    self?.parent.onShare(item)
                } : nil,
                compress: { [weak self] in
                    guard let items = self?.selectedItems, !items.isEmpty else { return }
                    self?.parent.onCompress(items)
                },
                extract: items.count == 1 ? { [weak self] in
                    guard let item = self?.selectedItems.first else { return }
                    self?.parent.onExtract(item)
                } : nil,
                showInfo: items.count == 1 ? { [weak self] in self?.showInfoForSelection() } : nil
            )
        }

        @objc func tableDoubleClicked(_ sender: NSTableView) {
            guard sender.clickedRow >= 0, parent.items.indices.contains(sender.clickedRow) else { return }
            parent.onActivate(parent.items[sender.clickedRow])
        }
    }
}

private final class ClosureMenuTarget: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func fire() { handler() }
}

private func closureMenuItem(title: String, handler: @escaping () -> Void) -> NSMenuItem {
    let target = ClosureMenuTarget(handler: handler)
    let item = NSMenuItem(title: title, action: #selector(ClosureMenuTarget.fire), keyEquivalent: "")
    item.target = target
    item.toolTip = title
    // `target` is weak on NSMenuItem; representedObject keeps it alive for the menu's lifetime.
    item.representedObject = target
    return item
}

private func makeFileContextMenu(
    availability: FileActionAvailability,
    canExtractSelectedItem: Bool,
    activate: (() -> Void)?,
    download: @escaping () -> Void,
    rename: (() -> Void)?,
    delete: @escaping () -> Void,
    copy: @escaping () -> Void,
    share: (() -> Void)?,
    compress: @escaping () -> Void,
    extract: (() -> Void)?,
    showInfo: (() -> Void)?
) -> NSMenu {
    let menu = NSMenu()
    if let activate {
        menu.addItem(closureMenuItem(title: String(localized: "common.button.open"), handler: activate))
    }
    if availability.canDownload {
        menu.addItem(closureMenuItem(title: String(localized: "files.button.download"), handler: download))
    }

    if availability.canShare, let share {
        menu.addItem(closureMenuItem(title: String(localized: "common.action.create_share_link"), handler: share))
    }
    if availability.canCompress || (availability.canExtract && canExtractSelectedItem) {
        menu.addItem(NSMenuItem.separator())
        if availability.canCompress {
            menu.addItem(closureMenuItem(title: String(localized: "common.button.compress"), handler: compress))
        }
        if availability.canExtract, canExtractSelectedItem, let extract {
            menu.addItem(closureMenuItem(title: String(localized: "common.button.extract"), handler: extract))
        }
    }
    if availability.canCopyMove || availability.canRename || availability.canDelete {
        menu.addItem(NSMenuItem.separator())
        if availability.canCopyMove {
            menu.addItem(closureMenuItem(title: String(localized: "common.button.copy"), handler: copy))
        }
        if availability.canRename, let rename {
            menu.addItem(closureMenuItem(title: String(localized: "common.menu.rename"), handler: rename))
        }
        if availability.canDelete {
            menu.addItem(closureMenuItem(title: String(localized: "common.menu.delete"), handler: delete))
        }
    }

    if let showInfo {
        if !menu.items.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }
        menu.addItem(closureMenuItem(title: String(localized: "common.button.get_info"), handler: showInfo))
    }
    return menu
}

final class KeyboardTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onGoUp: (() -> Void)?
    var onDownload: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    var onMoveHere: (() -> Void)?
    var onShowInfo: (() -> Void)?
    var menuProvider: ((NSEvent) -> NSMenu?)?
    private var selectionBeforeRightMouseDown: IndexSet?

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        switch event.keyCode {
        case 125 where command:
            fire(onActivate, for: event)
        case 126 where command:
            fire(onGoUp, for: event)
        case 36, 76:
            fire(onRename, for: event)
        case 51 where command:
            fire(onDelete, for: event)
        case 8 where command:
            fire(onCopy, for: event)
        // ⌘⌥V before ⌘V: the "command" clause alone would match ⌘⌥V as well.
        case 9 where command && option:
            fire(onMoveHere, for: event)
        case 9 where command:
            fire(onPaste, for: event)
        case 2 where command && shift:
            fire(onDownload, for: event)
        case 34 where command:
            fire(onShowInfo, for: event)
        default:
            super.keyDown(with: event)
        }
    }

    /// Screens wire only the actions they offer; an unwired shortcut follows the responder
    /// chain instead of being silently swallowed by its case above.
    private func fire(_ handler: (() -> Void)?, for event: NSEvent) {
        if let handler { handler() } else { super.keyDown(with: event) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        if clickedRow >= 0 {
            let selection = Self.contextMenuSelection(
                clickedRow: clickedRow,
                currentSelection: selectedRowIndexes,
                selectionBeforeRightMouseDown: selectionBeforeRightMouseDown
            )
            selectRowIndexes(selection, byExtendingSelection: false)
        }
        return menuProvider?(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        selectionBeforeRightMouseDown = selectedRowIndexes
        super.rightMouseDown(with: event)
        selectionBeforeRightMouseDown = nil
    }

    static func contextMenuSelection(
        clickedRow: Int,
        currentSelection: IndexSet,
        selectionBeforeRightMouseDown: IndexSet?
    ) -> IndexSet {
        guard let previousSelection = selectionBeforeRightMouseDown,
              previousSelection.count > 1,
              previousSelection.contains(clickedRow) else {
            return currentSelection
        }
        return previousSelection
    }
}

/// Shared base for the cells of a File Station row. Each column is its own accessibility
/// element — a row folded into one element buries the values the columns exist to expose —
/// so the row's actions have to travel with every cell.
class FileRowCellView: NSTableCellView {
    var onPress: (() -> Void)?
    var onDownload: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: (() -> Void)?
    var onShare: (() -> Void)?
    var onCompress: (() -> Void)?
    var onExtract: (() -> Void)?
    var onShowInfo: (() -> Void)?
    var actionAvailability = FileActionAvailability(
        canDownload: false,
        canRename: false,
        canDelete: false,
        canCopyMove: false,
        canShare: false,
        canCompress: false,
        canExtract: false
    )
    var canExtractSelectedItem = false

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = [NSAccessibilityCustomAction]()
        if actionAvailability.canDownload {
            appendAction(named: String(localized: "files.button.download"), handler: onDownload, to: &actions)
        }
        if actionAvailability.canShare {
            appendAction(named: String(localized: "common.action.create_share_link"), handler: onShare, to: &actions)
        }
        if actionAvailability.canCompress {
            appendAction(named: String(localized: "files.button.compress"), handler: onCompress, to: &actions)
        }
        if actionAvailability.canExtract, canExtractSelectedItem {
            appendAction(named: String(localized: "common.button.extract"), handler: onExtract, to: &actions)
        }
        if actionAvailability.canCopyMove {
            appendAction(named: String(localized: "common.button.copy"), handler: onCopy, to: &actions)
        }
        if actionAvailability.canRename {
            appendAction(named: String(localized: "common.button.rename"), handler: onRename, to: &actions)
        }
        if actionAvailability.canDelete {
            appendAction(named: String(localized: "common.button.delete"), handler: onDelete, to: &actions)
        }
        appendAction(named: String(localized: "common.button.get_info"), handler: onShowInfo, to: &actions)
        return actions.isEmpty ? nil : actions
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard onDownload != nil else { return false }
        let menu = makeFileContextMenu(
            availability: actionAvailability,
            canExtractSelectedItem: canExtractSelectedItem,
            activate: onPress,
            download: { [weak self] in self?.onDownload?() },
            rename: onRename,
            delete: { [weak self] in self?.onDelete?() },
            copy: { [weak self] in self?.onCopy?() },
            share: onShare,
            compress: { [weak self] in self?.onCompress?() },
            extract: onExtract,
            showInfo: onShowInfo
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

final class FileNameCellView: FileRowCellView {
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
        // The icon only doubles the kind column; announcing it would repeat that word.
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

    func configure(with item: FileStationItem) {
        iconView.image = NSImage(
            systemSymbolName: item.isdir ? "folder" : "doc",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = item.isdir ? .controlAccentColor : .secondaryLabelColor
        nameField.stringValue = item.name
        setAccessibilityLabel(item.name)
    }
}

final class FileValueCellView: FileRowCellView {
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
        // value twice, and would put the dash back on a cell meant to stay silent.
        valueField.setAccessibilityElement(false)

        addSubview(valueField)
        textField = valueField

        NSLayoutConstraint.activate([
            valueField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            valueField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            valueField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(value: String, alignment: NSTextAlignment, truncatesHead: Bool) {
        valueField.stringValue = value
        valueField.alignment = alignment
        valueField.lineBreakMode = truncatesHead ? .byTruncatingHead : .byTruncatingTail
        setAccessibilityLabel(value == FileStationItem.absentValue ? "" : value)
    }
}
