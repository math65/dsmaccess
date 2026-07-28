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
    let holder: DSMPermissionHolder
    let isEnabled: Bool
    let onChange: (DSMSharePermission, DSMSharePermissionLevel?) -> Void

    /// Colonne du choix « aucun droit propre », que DSM obtient en décochant ses cases.
    /// Des boutons radio ne se décochant pas, l'héritage devient un choix à part entière.
    private static let inheritColumn = "inherit"
    private static let textColumns = ["name", "group"]

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
        if holder.inheritsFromGroups {
            addColumn(to: table, identifier: "group", title: String(localized: "Droit de groupe"), width: 150)
        }
        addColumn(
            to: table,
            identifier: Self.inheritColumn,
            title: noRightTitle,
            width: 130
        )
        for level in DSMSharePermissionLevel.allCases {
            addColumn(
                to: table,
                identifier: level.rawValue,
                title: level.label,
                width: 110,
                help: level == .noAccess ? denialHelp : nil
            )
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
        let previous = context.coordinator.rowPresentationKeys
        guard previous != keys else { return }
        context.coordinator.rowPresentationKeys = keys

        // Cocher un choix en décoche un autre sur la même ligne : recharger cette seule ligne
        // évite de déplacer le curseur VoiceOver hors de la case que l'on vient d'activer.
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

    /// Sans héritage possible, « hériter » n'a pas de sens : pour un groupe, la première
    /// colonne dit simplement que le groupe n'accorde rien sur ce dossier.
    private var noRightTitle: String {
        holder.inheritsFromGroups
            ? String(localized: "Hériter du groupe")
            : String(localized: "Aucun droit")
    }

    /// Un refus posé sur un groupe l'emporte sur le droit propre de chaque membre : c'est
    /// la seule colonne dont la portée dépasse ce que la ligne montre.
    private var denialHelp: String? {
        guard !holder.inheritsFromGroups else { return nil }
        return String(
            localized: "Un refus accordé à un groupe s’applique à tous ses membres et ne peut pas être levé compte par compte."
        )
    }

    private func addColumn(
        to table: NSTableView,
        identifier: String,
        title: String,
        width: CGFloat,
        help: String? = nil
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = 80
        column.headerToolTip = help
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
                cell.textField?.stringValue = identifier.rawValue == "name"
                    ? permission.name
                    : Self.groupText(permission)
                return cell
            }

            let level = DSMSharePermissionLevel(rawValue: identifier.rawValue)
            guard level != nil || identifier.rawValue == SharePermissionTableView.inheritColumn else {
                return nil
            }
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PermissionChoiceCell
                ?? PermissionChoiceCell(identifier: identifier)
            cell.configure(
                isOn: permission.granted == level,
                isEnabled: parent.isEnabled,
                label: String(localized: "\(permission.name), \(level?.label ?? parent.noRightTitle)"),
                help: level == .noAccess ? parent.denialHelp : nil,
                target: self,
                action: #selector(choiceChanged(_:))
            )
            return cell
        }

        /// La ligne entière se lit d'une traite quand VoiceOver la parcourt en mode ligne.
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            guard parent.permissions.indices.contains(row) else { return nil }
            let permission = parent.permissions[row]
            let rowView = NSTableRowView()
            rowView.setAccessibilityLabel(rowLabel(permission))
            return rowView
        }

        @objc private func choiceChanged(_ sender: NSButton) {
            guard let tableView else { return }
            let row = tableView.row(for: sender)
            guard parent.permissions.indices.contains(row) else { return }
            // La colonne d'héritage n'a pas de niveau : elle efface le droit propre.
            let level = DSMSharePermissionLevel(rawValue: sender.identifier?.rawValue ?? "")
            parent.onChange(parent.permissions[row], level)
        }

        /// Le droit de groupe se lit seul, sauf quand il prive le choix du compte de tout
        /// effet : la règle NA > RW > RO doit alors se voir sur la ligne concernée.
        private static func groupText(_ permission: DSMSharePermission) -> String {
            guard let inherited = permission.inherited else {
                return String(localized: "Aucun")
            }
            guard permission.granted != nil, permission.effective != permission.granted else {
                return inherited.label
            }
            return String(localized: "\(inherited.label) — l’emporte")
        }

        private func rowLabel(_ permission: DSMSharePermission) -> String {
            guard parent.holder.inheritsFromGroups else { return permission.name }
            guard permission.inherited != nil else {
                return String(localized: "\(permission.name), aucun droit de groupe")
            }
            return String(localized: "\(permission.name), droit de groupe : \(Self.groupText(permission))")
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

private final class PermissionChoiceCell: NSTableCellView {
    private let choice = NSButton(radioButtonWithTitle: "", target: nil, action: nil)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        choice.identifier = identifier
        choice.translatesAutoresizingMaskIntoConstraints = false
        addSubview(choice)
        NSLayoutConstraint.activate([
            choice.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            choice.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    func configure(
        isOn: Bool,
        isEnabled: Bool,
        label: String,
        help: String?,
        target: AnyObject,
        action: Selector
    ) {
        choice.state = isOn ? .on : .off
        choice.isEnabled = isEnabled
        choice.target = target
        choice.action = action
        choice.setAccessibilityLabel(label)
        choice.setAccessibilityHelp(help)
        choice.toolTip = help
    }
}
