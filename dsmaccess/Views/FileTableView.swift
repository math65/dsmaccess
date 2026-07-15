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

struct FileTableView: NSViewRepresentable {
    var items: [FileStationItem]
    @Binding var selection: Set<String>
    var focusRequestID: Int
    var canWrite: Bool
    var showsPath: Bool
    var canExtract: (FileStationItem) -> Bool
    var onActivate: (FileStationItem) -> Void
    var onDownload: ([FileStationItem]) -> Void
    var onRename: (FileStationItem) -> Void
    var onDelete: ([FileStationItem]) -> Void
    var onCopy: ([FileStationItem]) -> Void
    var onCut: ([FileStationItem]) -> Void
    var onShare: (FileStationItem) -> Void
    var onCompress: ([FileStationItem]) -> Void
    var onExtract: (FileStationItem) -> Void
    var onShowInfo: (FileStationItem) -> Void
    var onGoUp: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyboardTableView()
        table.headerView = nil
        table.rowHeight = 28
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.style = .inset
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        table.onActivate = { [weak coordinator = context.coordinator] in coordinator?.activateSelection() }
        table.onGoUp = { [weak coordinator = context.coordinator] in coordinator?.parent.onGoUp() }
        table.onDownload = { [weak coordinator = context.coordinator] in coordinator?.downloadSelection() }
        table.onRename = { [weak coordinator = context.coordinator] in coordinator?.renameSelection() }
        table.onDelete = { [weak coordinator = context.coordinator] in coordinator?.deleteSelection() }
        table.onCopy = { [weak coordinator = context.coordinator] in coordinator?.copySelection() }
        table.onCut = { [weak coordinator = context.coordinator] in coordinator?.cutSelection() }
        table.onShowInfo = { [weak coordinator = context.coordinator] in coordinator?.showInfoForSelection() }
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
        let currentRows = items.map {
            "\(canWrite)|\(showsPath)|\($0.isdir)|\($0.path)|\($0.name)|\($0.detailText ?? "")"
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
            }
        }
        context.coordinator.isApplyingSelection = false
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?
        var isApplyingSelection = false
        var rowPresentationKeys = [String]()
        var lastFocusRequestID = 0

        init(_ parent: FileTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.items.indices.contains(row) else { return nil }
            let item = parent.items[row]
            let identifier = NSUserInterfaceItemIdentifier("FileCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? FileCellView)
                ?? FileCellView(identifier: identifier)
            cell.configure(with: item, showsPath: parent.showsPath)
            cell.canWrite = parent.canWrite
            cell.canExtract = parent.canWrite && parent.canExtract(item)
            cell.onPress = { [weak self] in self?.parent.onActivate(item) }
            cell.onDownload = { [weak self] in self?.parent.onDownload([item]) }
            cell.onRename = { [weak self] in self?.parent.onRename(item) }
            cell.onDelete = { [weak self] in self?.parent.onDelete([item]) }
            cell.onCopy = { [weak self] in self?.parent.onCopy([item]) }
            cell.onCut = { [weak self] in self?.parent.onCut([item]) }
            cell.onShare = { [weak self] in self?.parent.onShare(item) }
            cell.onCompress = { [weak self] in self?.parent.onCompress([item]) }
            cell.onExtract = { [weak self] in self?.parent.onExtract(item) }
            cell.onShowInfo = { [weak self] in self?.parent.onShowInfo(item) }
            return cell
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
            guard parent.canWrite, selectedItems.count == 1, let item = selectedItems.first else { return }
            parent.onRename(item)
        }

        func deleteSelection() {
            let items = selectedItems
            guard parent.canWrite, !items.isEmpty else { return }
            parent.onDelete(items)
        }

        func copySelection() {
            let items = selectedItems
            guard parent.canWrite, !items.isEmpty else { return }
            parent.onCopy(items)
        }

        func cutSelection() {
            let items = selectedItems
            guard parent.canWrite, !items.isEmpty else { return }
            parent.onCut(items)
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
                canWrite: parent.canWrite,
                canExtract: items.count == 1 && parent.canExtract(items[0]),
                activate: items.count == 1 ? { [weak self] in self?.activateSelection() } : nil,
                download: { [weak self] in self?.downloadSelection() },
                rename: items.count == 1 ? { [weak self] in self?.renameSelection() } : nil,
                delete: { [weak self] in self?.deleteSelection() },
                copy: { [weak self] in self?.copySelection() },
                cut: { [weak self] in self?.cutSelection() },
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
    // `target` est faible sur NSMenuItem ; representedObject le conserve pendant la vie du menu.
    item.representedObject = target
    return item
}

private func makeFileContextMenu(
    canWrite: Bool,
    canExtract: Bool,
    activate: (() -> Void)?,
    download: @escaping () -> Void,
    rename: (() -> Void)?,
    delete: @escaping () -> Void,
    copy: @escaping () -> Void,
    cut: @escaping () -> Void,
    share: (() -> Void)?,
    compress: @escaping () -> Void,
    extract: (() -> Void)?,
    showInfo: (() -> Void)?
) -> NSMenu {
    let menu = NSMenu()
    if let activate {
        menu.addItem(closureMenuItem(title: String(localized: "Ouvrir"), handler: activate))
    }
    menu.addItem(closureMenuItem(title: String(localized: "Télécharger"), handler: download))

    if canWrite {
        if let share {
            menu.addItem(closureMenuItem(title: String(localized: "Créer un lien de partage"), handler: share))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(closureMenuItem(title: String(localized: "Compresser…"), handler: compress))
        if canExtract, let extract {
            menu.addItem(closureMenuItem(title: String(localized: "Extraire"), handler: extract))
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(closureMenuItem(title: String(localized: "Copier"), handler: copy))
        menu.addItem(closureMenuItem(title: String(localized: "Déplacer (couper)"), handler: cut))
        if let rename {
            menu.addItem(closureMenuItem(title: String(localized: "Renommer…"), handler: rename))
        }
        menu.addItem(closureMenuItem(title: String(localized: "Supprimer…"), handler: delete))
    }

    if let showInfo {
        menu.addItem(NSMenuItem.separator())
        menu.addItem(closureMenuItem(title: String(localized: "Lire les informations"), handler: showInfo))
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
    var onCut: (() -> Void)?
    var onShowInfo: (() -> Void)?
    var menuProvider: ((NSEvent) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 125 where command:
            onActivate?()
        case 126 where command:
            onGoUp?()
        case 36, 76:
            onRename?()
        case 51 where command:
            onDelete?()
        case 8 where command:
            onCopy?()
        case 7 where command:
            onCut?()
        case 2 where command && shift:
            onDownload?()
        case 34 where command:
            onShowInfo?()
        default:
            super.keyDown(with: event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(event)
    }
}

final class FileCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    var onPress: (() -> Void)?
    var onDownload: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onShare: (() -> Void)?
    var onCompress: (() -> Void)?
    var onExtract: (() -> Void)?
    var onShowInfo: (() -> Void)?
    var canWrite = false
    var canExtract = false

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
        detailField.translatesAutoresizingMaskIntoConstraints = false
        nameField.lineBreakMode = .byTruncatingTail
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailField.textColor = .secondaryLabelColor
        detailField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailField.alignment = .right
        detailField.lineBreakMode = .byTruncatingHead
        detailField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(iconView)
        addSubview(nameField)
        addSubview(detailField)
        imageView = iconView
        textField = nameField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailField.leadingAnchor.constraint(greaterThanOrEqualTo: nameField.trailingAnchor, constant: 12),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailField.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.55),
        ])
    }

    func configure(with item: FileStationItem, showsPath: Bool) {
        iconView.image = NSImage(
            systemSymbolName: item.isdir ? "folder" : "doc",
            accessibilityDescription: nil
        )
        iconView.contentTintColor = item.isdir ? .controlAccentColor : .secondaryLabelColor
        nameField.stringValue = item.name
        detailField.stringValue = showsPath ? item.path : item.detailText ?? ""
        setAccessibilityLabel(showsPath ? "\(item.accessibilityLabel), \(item.path)" : item.accessibilityLabel)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = [NSAccessibilityCustomAction]()
        appendAction(named: String(localized: "Télécharger"), handler: onDownload, to: &actions)
        if canWrite {
            appendAction(named: String(localized: "Créer un lien de partage"), handler: onShare, to: &actions)
            appendAction(named: String(localized: "Compresser"), handler: onCompress, to: &actions)
            if canExtract {
                appendAction(named: String(localized: "Extraire"), handler: onExtract, to: &actions)
            }
            appendAction(named: String(localized: "Copier"), handler: onCopy, to: &actions)
            appendAction(named: String(localized: "Déplacer (couper)"), handler: onCut, to: &actions)
            appendAction(named: String(localized: "Renommer"), handler: onRename, to: &actions)
            appendAction(named: String(localized: "Supprimer"), handler: onDelete, to: &actions)
        }
        appendAction(named: String(localized: "Lire les informations"), handler: onShowInfo, to: &actions)
        return actions.isEmpty ? nil : actions
    }

    override func accessibilityPerformShowMenu() -> Bool {
        guard onDownload != nil else { return false }
        let menu = makeFileContextMenu(
            canWrite: canWrite,
            canExtract: canExtract,
            activate: onPress,
            download: { [weak self] in self?.onDownload?() },
            rename: onRename,
            delete: { [weak self] in self?.onDelete?() },
            copy: { [weak self] in self?.onCopy?() },
            cut: { [weak self] in self?.onCut?() },
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
