//
//  SharePermissionTableView.swift
//  dsmaccess
//
//  Grille des permissions en NSTableView : colonnes réelles, en-têtes, navigation flèches
//  native et sémantique de tableau pour VoiceOver.
//

import AppKit
import SwiftUI

struct SharePermissionTableView: NSViewRepresentable {
    let permissions: [DSMSharePermission]
    let isEnabled: Bool
    let onChange: (DSMSharePermission, DSMSharePermissionLevel?) -> Void

    private static let textColumns = ["name", "effective", "inherited"]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.rowHeight = 24
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel(String(localized: "Permissions par dossier partagé"))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        addColumn(to: table, identifier: "name", title: String(localized: "Dossier partagé"), width: 170)
        addColumn(to: table, identifier: "effective", title: String(localized: "Appliqué"), width: 110)
        addColumn(to: table, identifier: "inherited", title: String(localized: "Droit de groupe"), width: 120)
        for level in DSMSharePermissionLevel.allCases {
            addColumn(to: table, identifier: level.rawValue, title: level.label, width: 110)
        }

        context.coordinator.tableView = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = nsView.documentView as? NSTableView else { return }
        let keys = permissions.map {
            "\($0.name)|\($0.granted?.rawValue ?? "-")|\($0.inherited?.rawValue ?? "-")|\(isEnabled)"
        }
        guard context.coordinator.rowPresentationKeys != keys else { return }
        context.coordinator.rowPresentationKeys = keys
        table.reloadData()
    }

    private func addColumn(
        to table: NSTableView,
        identifier: String,
        title: String,
        width: CGFloat
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = 80
        table.addTableColumn(column)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: SharePermissionTableView
        weak var tableView: NSTableView?
        var rowPresentationKeys = [String]()

        init(_ parent: SharePermissionTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.permissions.count }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableColumn, parent.permissions.indices.contains(row) else { return nil }
            let permission = parent.permissions[row]
            let identifier = tableColumn.identifier

            if SharePermissionTableView.textColumns.contains(identifier.rawValue) {
                let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                    ?? Self.makeTextCell(identifier: identifier)
                cell.textField?.stringValue = text(for: identifier.rawValue, permission: permission)
                return cell
            }

            guard let level = DSMSharePermissionLevel(rawValue: identifier.rawValue) else { return nil }
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PermissionCheckboxCell
                ?? PermissionCheckboxCell(identifier: identifier)
            cell.configure(
                isOn: permission.granted == level,
                isEnabled: parent.isEnabled,
                label: String(localized: "\(permission.name), \(level.label)"),
                target: self,
                action: #selector(toggleChanged(_:))
            )
            return cell
        }

        /// La ligne entière se lit d'une traite quand VoiceOver la parcourt en mode ligne.
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard parent.permissions.indices.contains(row) else { return nil }
            let permission = parent.permissions[row]
            let rowView = NSTableRowView()
            rowView.setAccessibilityLabel(Self.rowLabel(permission))
            return rowView
        }

        @objc private func toggleChanged(_ sender: NSButton) {
            guard let tableView,
                  let level = DSMSharePermissionLevel(rawValue: sender.identifier?.rawValue ?? "")
            else { return }
            let row = tableView.row(for: sender)
            guard parent.permissions.indices.contains(row) else { return }
            let permission = parent.permissions[row]
            // Décocher la case active ramène le dossier au seul droit hérité, comme dans DSM.
            parent.onChange(permission, sender.state == .on ? level : nil)
        }

        private func text(for column: String, permission: DSMSharePermission) -> String {
            switch column {
            case "name": return permission.name
            case "effective": return permission.effective.label
            default: return permission.inherited?.label ?? String(localized: "Aucun")
            }
        }

        private static func rowLabel(_ permission: DSMSharePermission) -> String {
            if let inherited = permission.inherited {
                return String(
                    localized: "\(permission.name), appliqué : \(permission.effective.label), droit de groupe : \(inherited.label)"
                )
            }
            return String(
                localized: "\(permission.name), appliqué : \(permission.effective.label), aucun droit de groupe"
            )
        }

        private static func makeTextCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
    }
}

private final class PermissionCheckboxCell: NSTableCellView {
    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        checkbox.identifier = identifier
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    func configure(
        isOn: Bool,
        isEnabled: Bool,
        label: String,
        target: AnyObject,
        action: Selector
    ) {
        checkbox.state = isOn ? .on : .off
        checkbox.isEnabled = isEnabled
        checkbox.target = target
        checkbox.action = action
        checkbox.setAccessibilityLabel(label)
    }
}
