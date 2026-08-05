//
//  FolderPickerTableView.swift
//  dsmaccess
//
//  Native single-selection table for the shared-folder picker, with the Finder-style
//  keyboard handling of the File Station browser: arrows to move, ⌘↓ to enter a folder,
//  ⌘↑ to climb back out.
//

@preconcurrency import AppKit
import SwiftUI

/// One browsable folder. The picker lists shared folders at its root and File Station
/// folders below them, so it carries only what both have.
struct FolderPickerRow: Equatable, Identifiable {
    let name: String
    let path: String

    var id: String { path }
}

struct FolderPickerTableView: NSViewRepresentable {
    var rows: [FolderPickerRow]
    @Binding var selection: String?
    var focusRequestID: Int
    var onOpen: (FolderPickerRow) -> Void
    var onGoUp: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyboardTableView()
        table.headerView = nil
        table.rowHeight = 28
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.style = .inset
        table.setAccessibilityLabel(String(localized: "common.folder_picker.table.label"))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        table.onActivate = { [weak coordinator = context.coordinator] in coordinator?.openSelection() }
        table.onGoUp = { [weak coordinator = context.coordinator] in coordinator?.parent.onGoUp() }

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
        let currentRows = rows.map { "\($0.path)|\($0.name)" }
        if context.coordinator.rowPresentationKeys != currentRows {
            table.reloadData()
            context.coordinator.rowPresentationKeys = currentRows
        }
        let selectedRows = IndexSet(rows.indices.filter { rows[$0].path == selection })
        table.selectRowIndexes(selectedRows, byExtendingSelection: false)
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            if let row = selectedRows.first,
               let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) {
                table.window?.makeFirstResponder(table)
                NSAccessibility.post(element: cell, notification: .focusedUIElementChanged)
            } else if rows.isEmpty {
                // An empty folder offers no row to focus, yet the table must still be first
                // responder: it is what carries ⌘↑ back out. Deferred, because claiming it
                // during this update is undone by the empty-state overlay appearing right
                // after. No accessibility notification: the VoiceOver cursor belongs on the
                // message.
                Task { [weak table] in
                    guard let table, table.window != nil else { return }
                    table.window?.makeFirstResponder(table)
                }
            }
        }
        context.coordinator.isApplyingSelection = false
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FolderPickerTableView
        weak var tableView: NSTableView?
        var isApplyingSelection = false
        var rowPresentationKeys = [String]()
        var lastFocusRequestID = 0

        init(_ parent: FolderPickerTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.rows.indices.contains(row) else { return nil }
            let folder = parent.rows[row]
            let identifier = NSUserInterfaceItemIdentifier("FolderPickerCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? FolderPickerCellView)
                ?? FolderPickerCellView(identifier: identifier)
            cell.configure(with: folder)
            cell.onPress = { [weak self] in self?.parent.onOpen(folder) }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingSelection else { return }
            guard let tableView else { return }
            let row = tableView.selectedRow
            parent.selection = parent.rows.indices.contains(row) ? parent.rows[row].path : nil
        }

        func openSelection() {
            guard let tableView, parent.rows.indices.contains(tableView.selectedRow) else { return }
            parent.onOpen(parent.rows[tableView.selectedRow])
        }

        @objc func tableDoubleClicked(_ sender: NSTableView) {
            guard sender.clickedRow >= 0, parent.rows.indices.contains(sender.clickedRow) else { return }
            parent.onOpen(parent.rows[sender.clickedRow])
        }
    }
}

final class FolderPickerCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    var onPress: (() -> Void)?

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
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
        ])
    }

    func configure(with folder: FolderPickerRow) {
        iconView.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        iconView.contentTintColor = .controlAccentColor
        nameField.stringValue = folder.name
        // Every row here is a folder and the table already says so: repeating the kind on
        // each line would be narration for nothing.
        setAccessibilityLabel(folder.name)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
