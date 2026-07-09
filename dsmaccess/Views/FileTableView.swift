//
//  FileTableView.swift
//  dsmaccess
//
//  Navigateur File Station en AppKit (NSTableView) exposé à SwiftUI via NSViewRepresentable.
//  On descend en AppKit UNIQUEMENT pour cette liste : NSTableView donne la navigation
//  clavier native (flèches) et l'accessibilité VoiceOver de première classe que la List
//  SwiftUI ne fournit pas correctement sur macOS. Clavier façon Finder :
//    · ↑ / ↓        : parcourir (natif)
//    · Cmd-↓ / Entrée : entrer dans le dossier sélectionné
//    · Cmd-↑         : remonter au dossier parent
//    · VO-Espace     : activer la ligne (ouvre le dossier) via accessibilityPerformPress
//

import AppKit
import SwiftUI

struct FileTableView: NSViewRepresentable {
    var items: [FileStationItem]
    var onOpen: (FileStationItem) -> Void
    var onGoUp: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = KeyboardTableView()
        table.headerView = nil
        table.rowHeight = 28
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.style = .inset
        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        // Clavier : ouvrir la ligne sélectionnée / remonter.
        table.onActivate = { [weak table] in
            guard let table, table.selectedRow >= 0 else { return }
            context.coordinator.activateRow(table.selectedRow)
        }
        table.onGoUp = { context.coordinator.parent.onGoUp() }

        // Souris : double-clic pour ouvrir.
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
        guard let table = nsView.documentView as? NSTableView else { return }
        table.reloadData()
        // Point de départ clavier/VoiceOver : sélectionne la 1re ligne si la sélection
        // courante est vide ou hors bornes (typiquement après une navigation).
        if !items.isEmpty && (table.selectedRow < 0 || table.selectedRow >= items.count) {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?

        init(_ parent: FileTableView) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard parent.items.indices.contains(row) else { return nil }
            let item = parent.items[row]
            let id = NSUserInterfaceItemIdentifier("FileCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? FileCellView) ?? FileCellView(identifier: id)
            cell.configure(with: item)
            cell.onPress = { [weak self] in self?.activate(item) }
            return cell
        }

        func activateRow(_ row: Int) {
            guard parent.items.indices.contains(row) else { return }
            activate(parent.items[row])
        }

        /// Ouvre un dossier ; les fichiers sont ignorés (navigation seule) par le ViewModel.
        private func activate(_ item: FileStationItem) {
            parent.onOpen(item)
        }

        @objc func tableDoubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            if row >= 0 { activateRow(row) }
        }
    }
}

/// NSTableView qui mappe les touches façon Finder ; les flèches simples restent natives.
final class KeyboardTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onGoUp: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 125 where command:      // Cmd-↓ : entrer dans le dossier
            onActivate?()
        case 126 where command:      // Cmd-↑ : remonter
            onGoUp?()
        case 36, 76:                 // Entrée / Entrée (pavé numérique)
            onActivate?()
        default:
            super.keyDown(with: event)   // ↑ ↓ et le reste : comportement natif
        }
    }
}

/// Cellule : icône + nom + détail (taille · date), avec un libellé VoiceOver unifié et
/// une action « presser » (VO-Espace) qui ouvre le dossier.
final class FileCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
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
        detailField.translatesAutoresizingMaskIntoConstraints = false

        nameField.lineBreakMode = .byTruncatingTail
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailField.textColor = .secondaryLabelColor
        detailField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailField.alignment = .right
        detailField.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailField.setContentHuggingPriority(.required, for: .horizontal)

        addSubview(iconView)
        addSubview(nameField)
        addSubview(detailField)
        imageView = iconView
        textField = nameField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailField.leadingAnchor.constraint(greaterThanOrEqualTo: nameField.trailingAnchor, constant: 8),
            detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: FileStationItem) {
        iconView.image = NSImage(systemSymbolName: item.isdir ? "folder" : "doc", accessibilityDescription: nil)
        iconView.contentTintColor = item.isdir ? .controlAccentColor : .secondaryLabelColor
        nameField.stringValue = item.name
        detailField.stringValue = item.detailText ?? ""
        setAccessibilityLabel(item.accessibilityLabel)
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
