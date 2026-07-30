//
//  ApplicationPrivilegeTableView.swift
//  dsmaccess
//
//  Autorisations d'accès aux applications DSM, en NSTableView comme la grille des dossiers.
//

import AppKit
import SwiftUI

struct ApplicationPrivilegeTableView: NSViewRepresentable {
    let privileges: [DSMApplicationPrivilege]
    let isEnabled: Bool
    let onChange: (DSMApplicationPrivilege, DSMApplicationDecision?) -> Void

    /// Colonne du choix « pas de règle », que DSM obtient en supprimant la règle existante.
    private static let defaultColumn = "default"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.rowHeight = 24
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel(String(localized: "permissions.application.table.label"))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        addColumn(to: table, identifier: "name", title: String(localized: "permissions.application.column.name"), width: 220)
        addColumn(
            to: table,
            identifier: Self.defaultColumn,
            title: String(localized: "permissions.application.privilege.default"),
            width: 150
        )
        for decision in DSMApplicationDecision.allCases {
            addColumn(to: table, identifier: decision.rawValue, title: decision.label, width: 110)
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
        let keys = privileges.map { "\($0.appID)|\($0.decision?.rawValue ?? "-")|\(isEnabled)" }
        let previous = context.coordinator.rowPresentationKeys
        guard previous != keys else { return }
        context.coordinator.rowPresentationKeys = keys

        guard previous.count == keys.count else {
            table.reloadData()
            return
        }
        let changed = IndexSet(keys.indices.filter { previous[$0] != keys[$0] })
        table.reloadData(
            forRowIndexes: changed,
            columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns)
        )
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
        var parent: ApplicationPrivilegeTableView
        weak var tableView: NSTableView?
        var rowPresentationKeys = [String]()

        init(_ parent: ApplicationPrivilegeTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.privileges.count }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row: Int
        ) -> NSView? {
            guard let tableColumn, parent.privileges.indices.contains(row) else { return nil }
            let privilege = parent.privileges[row]
            let identifier = tableColumn.identifier

            if identifier.rawValue == "name" {
                let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                    ?? Self.makeTextCell(identifier: identifier)
                cell.textField?.stringValue = privilege.name
                return cell
            }

            let decision = DSMApplicationDecision(rawValue: identifier.rawValue)
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ApplicationChoiceCell
                ?? ApplicationChoiceCell(identifier: identifier)
            let title = decision?.label ?? privilege.fallbackLabel
            cell.configure(
                isOn: privilege.decision == decision,
                // Une règle limitée à des adresses précises se perdrait si l'app la
                // réécrivait en « toutes les adresses » : la ligne reste en lecture.
                isEnabled: parent.isEnabled && !privilege.restrictsAddresses,
                title: decision == nil ? privilege.fallbackLabel : "",
                label: String(localized: "common.format.pair", defaultValue: "\(privilege.name), \(title)"),
                help: privilege.restrictsAddresses
                    ? String(localized: "permissions.application.ip_rule.hint")
                    : nil,
                target: self,
                action: #selector(choiceChanged(_:))
            )
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard parent.privileges.indices.contains(row) else { return nil }
            let rowView = NSTableRowView()
            rowView.setAccessibilityLabel(parent.privileges[row].name)
            return rowView
        }

        @objc private func choiceChanged(_ sender: NSButton) {
            guard let tableView else { return }
            let row = tableView.row(for: sender)
            guard parent.privileges.indices.contains(row) else { return }
            let decision = DSMApplicationDecision(rawValue: sender.identifier?.rawValue ?? "")
            parent.onChange(parent.privileges[row], decision)
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

private final class ApplicationChoiceCell: NSTableCellView {
    private let choice = NSButton(radioButtonWithTitle: "", target: nil, action: nil)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        choice.identifier = identifier
        choice.translatesAutoresizingMaskIntoConstraints = false
        addSubview(choice)
        NSLayoutConstraint.activate([
            choice.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            choice.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            choice.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    func configure(
        isOn: Bool,
        isEnabled: Bool,
        title: String,
        label: String,
        help: String?,
        target: AnyObject,
        action: Selector
    ) {
        choice.title = title
        choice.state = isOn ? .on : .off
        choice.isEnabled = isEnabled
        choice.target = target
        choice.action = action
        choice.setAccessibilityLabel(label)
        choice.setAccessibilityHelp(help)
        choice.toolTip = help
    }
}
